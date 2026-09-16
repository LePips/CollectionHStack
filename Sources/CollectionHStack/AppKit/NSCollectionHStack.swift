#if os(macOS)
import AppKit
import SwiftUI

@MainActor
public protocol _NSCollectionHStack: AnyObject {
    func scrollTo(index: Int, animated: Bool)
    func snapshotReload()
    func index(id: some Hashable) -> Int?
}

extension CollectionHStack: NSViewRepresentable {
    public typealias NSViewType = NSCollectionHStack<Element, Data, ID, Content>

    public func makeNSView(context: Context) -> NSViewType {
        NSViewType(configuration: self)
    }

    public func updateNSView(_ view: NSViewType, context: Context) {
        view.update(
            configuration: self,
            isScrollEnabled: context.environment.isScrollEnabled,
            dynamicTypeSize: context.environment.dynamicTypeSize
        )
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSViewType, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFiniteAndPositive else { return nil }
        return nsView.fittingSize(forWidth: width)
    }

    public static func dismantleNSView(_ view: NSViewType, coordinator: ()) {
        view.disconnect()
    }
}

/// A virtualized AppKit collection with the same sizing and scrolling configuration as CollectionHStack.
public final class NSCollectionHStack<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
>: NSView, _NSCollectionHStack where Data.Element == Element, Data.Index == Int {
    private struct ItemID: Hashable {
        let id: ID
        let repetition: Int
    }

    private enum ScrollAnchor {
        case leading
        case trailing
        case item(index: Int, fraction: CGFloat, centered: Bool)
    }

    private var scrollAnchor: ScrollAnchor?
    private var anchorOffset: CGFloat?
    private var applyingLayout = false
    private var configuration: CollectionHStack<Element, Data, ID, Content>
    private var pendingInitialElementID: ID?
    let scrollView = CollectionScrollView()
    let collectionView = CollectionDocumentView()
    let collectionLayout = CollectionLayout()
    private var dataSource: NSCollectionViewDiffableDataSource<Int, ItemID>!
    private var dataIndex = CollectionDataIndex<ID>()
    private var indicesByID: [ID: Int] = [:]
    private var ids: [ID] {
        dataIndex.ids
    }

    private var itemCount = 0
    private var itemSizeCache = ItemSizeCache()
    private var variableSizes: [ID: CGSize] = [:]
    private var cachedSize: (width: CGFloat, item: CGSize, height: CGFloat)?
    private var appliedWidth: CGFloat?
    private var dynamicTypeSize: DynamicTypeSize?
    private var reachedEdges: Set<Edge> = []
    private var prefetched: Set<ID> = []
    private var settleWork: DispatchWorkItem?
    private var gestureStart: CGFloat?
    private var isAnimatingScroll = false
    private var scrollAnimationGeneration = 0
    private var updating = false
    private var disconnected = false
    private var intrinsicHeight: CGFloat = 0

    init(configuration: CollectionHStack<Element, Data, ID, Content>) {
        self.configuration = configuration
        super.init(frame: .zero)
        collectionLayout.horizontal = true
        collectionView.collectionViewLayout = collectionLayout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false
        collectionView.register(HostingCollectionViewItem.self, forItemWithIdentifier: .init("content"))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = collectionView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        dataSource = NSCollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collection, path, id in
            guard let self, let element = self.element(at: path.item, id: id.id) else { return nil }
            let item = collection.makeItem(withIdentifier: .init("content"), for: path) as! HostingCollectionViewItem
            item.configure(self.configuration.viewProvider(element), id: AnyHashable(id))
            return item
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.willScroll = { [weak self] in
            guard let self else { return }
            self.settleWork?.cancel()
            self.cancelScrollAnimation()
            if self.gestureStart == nil {
                self.gestureStart = self.scrollView.contentView.bounds.minX
            }
        }
        scrollView.didScroll = { [weak self] in self?.scheduleSettle(snap: true) }
        update(configuration: configuration, isScrollEnabled: true, dynamicTypeSize: .large)
        pendingInitialElementID = configuration.initialElementID.flatMap { target in
            ids.contains(target) ? target : nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override public var intrinsicContentSize: NSSize {
        CGSize(width: NSView.noIntrinsicMetric, height: intrinsicHeight)
    }

    override public func layout() {
        super.layout()
        guard bounds.width.isFiniteAndPositive else { return }
        if appliedWidth != bounds.width {
            applyLayout(forWidth: bounds.width)
            scheduleSettle(snap: false)
        }
        let contentSize = collectionLayout.collectionViewContentSize
        if collectionView.frame.size != contentSize {
            collectionView.setFrameSize(contentSize)
        }
        applyInitialElementIfNeeded()
    }

    private func applyInitialElementIfNeeded() {
        guard let target = pendingInitialElementID,
              scrollView.contentSize.width.isFiniteAndPositive,
              scrollView.contentSize.height.isFiniteAndPositive else { return }

        // Consume before scrolling, which can synchronously trigger another layout.
        pendingInitialElementID = nil
        guard let index = ids.firstIndex(of: target) else { return }
        scrollTo(index: index, animated: false)
    }

    func update(
        configuration new: CollectionHStack<Element, Data, ID, Content>,
        isScrollEnabled: Bool,
        dynamicTypeSize: DynamicTypeSize
    ) {
        let changedSizing = configuration.layout != new.layout || configuration.insets != new.insets
            || configuration.itemSpacing != new.itemSpacing || self.dynamicTypeSize != dynamicTypeSize
        let changedCarousel = configuration.isCarousel != new.isCarousel
        if configuration.proxy !== new.proxy, configuration.proxy.collectionView === self {
            configuration.proxy.collectionView = nil
        }
        var newIndex = dataIndex
        var newLookup = indicesByID
        let changedData = newIndex.update(from: new.data, id: new.id, prefix: new.dataPrefix, retainingLookup: &newLookup)
        if changedData {
            cancelPrefetch()
        }
        updating = changedData || changedCarousel
        configuration = new
        indicesByID = newLookup
        dataIndex = newIndex
        self.dynamicTypeSize = dynamicTypeSize
        configuration.proxy.collectionView = self
        scrollView.allowsScrolling = isScrollEnabled
        scrollView.horizontalScrollElasticity = new.allowBouncing ? .allowed : .none
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.clipsToBounds = new.clipsToBounds
        collectionView.clipsToBounds = new.clipsToBounds
        scrollView.clipsToBounds = new.clipsToBounds
        clipsToBounds = new.clipsToBounds

        if changedSizing || changedData {
            invalidateSizing()
        }

        if changedData || changedCarousel {
            let count = new.isCarousel && ids.isNotEmpty ? max(100, ids.count) : ids.count
            applySnapshot(count: count)
            reachedEdges.removeAll()
        } else {
            refreshVisibleItems()
        }

        needsLayout = true
        scheduleSettle(snap: false)
    }

    private func applySnapshot(count: Int) {
        updating = true
        scrollAnchor = nil
        anchorOffset = nil
        itemCount = ids.isEmpty ? 0 : count
        var snapshot = NSDiffableDataSourceSnapshot<Int, ItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems((0 ..< itemCount).map { itemID(at: $0) })
        dataSource.apply(snapshot, animatingDifferences: false)
        appliedWidth = nil
        updating = false
    }

    private func itemID(at index: Int) -> ItemID {
        ItemID(id: ids[index % ids.count], repetition: index / ids.count)
    }

    private func element(at position: Int, id: ID) -> Element? {
        if !updating, (0 ..< itemCount).contains(position) {
            return dataIndex.element(in: configuration.data, at: position)
        }
        return element(for: id)
    }

    private func element(for id: ID) -> Element? {
        guard let index = indicesByID[id] else { return nil }
        return configuration.data[index]
    }

    private func refreshVisibleItems() {
        for path in collectionView.indexPathsForVisibleItems() {
            guard let id = dataSource.itemIdentifier(for: path), let element = element(at: path.item, id: id.id),
                  let item = collectionView.item(at: path) as? HostingCollectionViewItem else { continue }
            item.configure(configuration.viewProvider(element), id: AnyHashable(id))
        }
    }

    private func invalidateSizing() {
        itemSizeCache = ItemSizeCache()
        cachedSize = nil
        variableSizes.removeAll(keepingCapacity: true)
        appliedWidth = nil
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    func fittingSize(forWidth width: CGFloat) -> CGSize {
        let sizes = computeSizes(forWidth: width)
        return CGSize(width: nonnegativeFinite(width), height: sizes.selfSize.height)
    }

    func computeSizes(forWidth width: CGFloat) -> (selfSize: CGSize, itemSize: CGSize) {
        guard width.isFiniteAndPositive else { return (.zero, .zero) }
        if let cachedSize, cachedSize.width == width {
            return (CGSize(width: NSView.noIntrinsicMetric, height: cachedSize.height), cachedSize.item)
        }
        let metrics = layoutMetrics
        let item = measure(width: metrics.itemWidth(for: width))
        let height = metrics.height(for: item)
        cachedSize = (width, item, height)
        return (CGSize(width: NSView.noIntrinsicMetric, height: height), item)
    }

    private var layoutMetrics: LayoutMetrics {
        LayoutMetrics(layout: configuration.layout, insets: configuration.insets, itemSpacing: configuration.itemSpacing)
    }

    private var rows: Int {
        layoutMetrics.rows
    }

    private func measure(width: CGFloat?) -> CGSize {
        guard ids.isNotEmpty else { return CGSize(width: width ?? 0, height: 0) }
        return itemSizeCache.size(width: width) {
            let element = configuration.data[configuration.data.startIndex]
            return measuredContentSize(configuration.viewProvider(element), width: width)
        }
    }

    private func applyLayout(forWidth width: CGFloat) {
        // Bounds changes during retiling can clamp the old pixel offset before we
        // get here. Use the anchor recorded while the previous layout was valid.
        let anchor = scrollAnchor
        applyingLayout = true
        settleWork?.cancel()
        cancelScrollAnimation()
        gestureStart = nil
        defer {
            applyingLayout = false
            // Keep the original fraction across consecutive resizes. Repeatedly
            // sampling AppKit's pixel-rounded offset would accumulate drift.
            if anchor != nil {
                anchorOffset = scrollView.contentView.bounds.minX
            } else {
                recordScrollAnchor()
            }
            updatePrefetch()
        }

        let result = computeSizes(forWidth: width)
        collectionLayout.lanes = rows
        collectionLayout.itemSize = result.itemSize
        collectionLayout.insets = configuration.insets.appKitInsets
        collectionLayout.itemSpacing = nonnegativeFinite(configuration.itemSpacing)
        collectionLayout.lineSpacing = nonnegativeFinite(configuration.itemSpacing)

        if case .selfSizingVariadicWidth = configuration.layout {
            collectionLayout.variableSizes = (0 ..< itemCount).compactMap { index in
                let item = itemID(at: index)
                if let size = variableSizes[item.id] {
                    return size
                }
                guard let element = element(at: index, id: item.id) else { return nil }
                let size = measuredContentSize(configuration.viewProvider(element))
                variableSizes[item.id] = size
                return size
            }
        } else {
            collectionLayout.variableSizes = []
        }

        collectionLayout.invalidateLayout()
        collectionLayout.prepare()
        collectionView.setFrameSize(collectionLayout.collectionViewContentSize)
        appliedWidth = width
        if let anchor {
            restoreScrollAnchor(anchor)
        }

        if intrinsicHeight != result.selfSize.height {
            intrinsicHeight = result.selfSize.height
            invalidateIntrinsicContentSize()
        }

        collectionView.needsLayout = true
    }

    private func recordScrollAnchor() {
        let viewport = scrollView.contentView.bounds
        // A resize notification can arrive before the new item metrics are applied.
        guard !applyingLayout, appliedWidth == bounds.width, appliedWidth == viewport.width else { return }
        // AppKit may round the restored origin to a backing pixel in a later pass.
        let tolerance = 1 / max(window?.backingScaleFactor ?? 1, 1)
        if let anchorOffset, abs(anchorOffset - viewport.minX) <= tolerance {
            return
        }
        anchorOffset = viewport.minX
        guard itemCount > 0 else {
            scrollAnchor = nil
            return
        }
        if viewport.minX <= 0.5 {
            scrollAnchor = .leading
        } else if viewport.minX >= maximumOffset - 0.5 {
            scrollAnchor = .trailing
        } else {
            let centered = configuration.scrollBehavior == .continuous || configuration.scrollBehavior == .fullPaging
            let reference = viewport.minX + (centered ? viewport.width / 2 : collectionLayout.insets.left)
            let attributes = collectionLayout.layoutAttributesForElements(in: viewport)
            let nearest = attributes.min {
                let lhs = centered ? $0.frame.midX : $0.frame.minX
                let rhs = centered ? $1.frame.midX : $1.frame.minX
                return abs(lhs - reference) < abs(rhs - reference)
            }
            guard let nearest, let index = nearest.indexPath?.item, nearest.frame.width.isFiniteAndPositive else { return }
            scrollAnchor = .item(index: index, fraction: (reference - nearest.frame.minX) / nearest.frame.width, centered: centered)
        }
    }

    private func restoreScrollAnchor(_ anchor: ScrollAnchor) {
        let offset: CGFloat
        switch anchor {
        case .leading:
            offset = 0
        case .trailing:
            offset = maximumOffset
        case let .item(index, fraction, centered):
            guard let attributes = collectionLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }
            let reference = centered ? scrollView.contentSize.width / 2 : collectionLayout.insets.left
            offset = attributes.frame.minX + attributes.frame.width * fraction - reference
        }
        scrollView.contentView.scroll(to: CGPoint(x: offset.clamped(to: 0 ... maximumOffset), y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    public func snapshotReload() {
        invalidateSizing()
        refreshVisibleItems()
    }

    public func index(id: some Hashable) -> Int? {
        ids.firstIndex { AnyHashable($0) == AnyHashable(id) }
    }

    public func scrollTo(index: Int, animated: Bool) {
        guard (0 ..< itemCount).contains(index) else { return }
        layoutSubtreeIfNeeded()
        guard let attributes = collectionLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }

        let target: CGFloat = switch configuration.scrollBehavior {
        case .continuousLeadingEdge, .columnPaging: attributes.frame.minX - configuration.insets.leading
        case .continuous, .fullPaging: attributes.frame.midX - scrollView.contentSize.width / 2
        }

        scroll(to: target, animated: animated)
    }

    private var maximumOffset: CGFloat {
        max(0, collectionLayout.collectionViewContentSize.width - scrollView.contentSize.width)
    }

    private func scroll(to offset: CGFloat, animated: Bool) {
        cancelScrollAnimation()
        gestureStart = nil

        let point = CGPoint(x: offset.clamped(to: 0 ... maximumOffset), y: 0)
        if animated, point != scrollView.contentView.bounds.origin {
            isAnimatingScroll = true
            scrollAnimationGeneration += 1
            let generation = scrollAnimationGeneration
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                scrollView.contentView.animator().setBoundsOrigin(point)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.scrollAnimationGeneration == generation, !self.disconnected else { return }
                    self.isAnimatingScroll = false
                    self.scheduleSettle(snap: false)
                }
            }
        } else {
            scrollView.contentView.scroll(to: point)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scheduleSettle(snap: false)
        }
    }

    private func cancelScrollAnimation() {
        guard isAnimatingScroll else { return }
        isAnimatingScroll = false
        scrollAnimationGeneration += 1

        let origin = scrollView.contentView.bounds.origin
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            scrollView.contentView.animator().setBoundsOrigin(origin)
        }
    }

    @objc
    private func boundsChanged() {
        guard !updating, !applyingLayout, !disconnected else { return }
        recordScrollAnchor()
        scheduleSettle(snap: gestureStart != nil)
        updatePrefetch()
    }

    private func scheduleSettle(snap: Bool) {
        settleWork?.cancel()
        guard !disconnected, !isAnimatingScroll, !scrollView.isTrackingScroll else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if snap || self.gestureStart != nil {
                self.scroll(
                    to: self.settledOffset(proposed: self.scrollView.contentView.bounds.minX, gestureStart: self.gestureStart),
                    animated: true
                )
            } else {
                self.publishScrollState()
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// Paging advances at most one column/page per gesture. Continuous alignment can cross many columns.
    func settledOffset(proposed: CGFloat, gestureStart: CGFloat?) -> CGFloat {
        let offset = proposed.clamped(to: 0 ... maximumOffset)
        guard configuration.scrollBehavior != .continuous else { return offset }

        if configuration.scrollBehavior == .fullPaging {
            let page = max(1, bounds.width - configuration.insets.leading - configuration.insets.trailing + configuration.itemSpacing)
            var targetPage = (offset / page).rounded()
            if let gestureStart {
                let startPage = (gestureStart / page).rounded()
                targetPage = targetPage.clamped(to: (startPage - 1) ... (startPage + 1))
            }
            return (targetPage * page).clamped(to: 0 ... maximumOffset)
        }

        let reference = configuration.scrollBehavior == .columnPaging ? (gestureStart ?? offset) : offset
        let rect = CGRect(x: reference - bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
        let columns = collectionLayout.layoutAttributesForElements(in: rect).filter { ($0.indexPath?.item ?? 0) % rows == 0 }
        let nearest = columns.min {
            abs($0.frame.minX - reference - configuration.insets.leading) < abs($1.frame.minX - reference - configuration.insets.leading)
        }

        guard let nearest, let index = nearest.indexPath?.item else { return offset }

        let candidates: [CGFloat]
        if configuration.scrollBehavior == .columnPaging, gestureStart != nil {
            candidates = [index - rows, index, index + rows].compactMap {
                collectionLayout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
                    .map { $0.frame.minX - configuration.insets.leading }
            }
        } else {
            // Preserve the trailing edge when the final column cannot be leading-aligned.
            if offset >= maximumOffset - 1 {
                return maximumOffset
            }
            candidates = columns.map { $0.frame.minX - configuration.insets.leading }
        }

        let target = candidates.min { abs($0 - offset) < abs($1 - offset) } ?? offset
        return target.clamped(to: 0 ... maximumOffset)
    }

    private func publishScrollState() {
        guard !updating else { return }
        let visible = collectionView.indexPathsForVisibleItems().map(\.item).sorted()
        let offset = scrollView.contentView.bounds.minX

        let leading: Bool = switch configuration.onReachedLeadingEdgeOffset {
        case let .offset(threshold): offset <= threshold
        case let .columns(count): (visible.first ?? Int.max) / rows < count
        }

        let trailing: Bool = switch configuration.onReachedTrailingEdgeOffset {
        case let .offset(threshold): offset >= maximumOffset - threshold
        case let .columns(count): (visible.last.map { $0 / rows } ?? Int.min) >= collectionLayout.groups - count
        }

        updateEdge(.leading, reached: ids.isNotEmpty && leading, action: configuration.onReachedLeadingEdge)

        if configuration.isCarousel, ids.isNotEmpty, offset >= maximumOffset - bounds.width {
            applySnapshot(count: itemCount + 100)
            needsLayout = true
        } else {
            updateEdge(.trailing, reached: ids.isNotEmpty && trailing, action: configuration.onReachedTrailingEdge)
        }

        if let binding = configuration.alignedLeadingElementID {
            var alignedID: ID?
            if configuration.scrollBehavior == .continuousLeadingEdge || configuration.scrollBehavior == .columnPaging {
                let tolerance = 1 / max(window?.backingScaleFactor ?? 1, 1)
                for index in visible {
                    guard let attributes = collectionLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
                    else { continue }
                    if abs(attributes.frame.minX - offset - configuration.insets.leading) <= tolerance {
                        alignedID = itemID(at: index).id
                        break
                    }
                }
            }
            if binding.wrappedValue != alignedID {
                binding.wrappedValue = alignedID
            }
        }

        configuration.didScrollToItems(visible.compactMap { (0 ..< itemCount).contains($0) ? dataIndex.element(
            in: configuration.data,
            at: $0
        ) : nil })
    }

    private func updateEdge(_ edge: Edge, reached: Bool, action: () -> Void) {
        if reached {
            if reachedEdges.insert(edge).inserted {
                action()
            }
        } else {
            reachedEdges.remove(edge)
        }
    }

    private func updatePrefetch() {
        guard ids.isNotEmpty else { return }
        let viewport = scrollView.contentView.bounds
        let visible = Set(collectionLayout.layoutAttributesForElements(in: viewport).compactMap { $0.indexPath?.item })
        let nearby = collectionLayout.layoutAttributesForElements(in: viewport.insetBy(dx: -viewport.width, dy: 0))

        let next = Set(nearby.compactMap { attributes -> ID? in
            guard let index = attributes.indexPath?.item, !visible.contains(index), (0 ..< itemCount).contains(index) else { return nil }
            return itemID(at: index).id
        })

        let cancelled = prefetched.subtracting(next).compactMap { element(for: $0) }
        let added = next.subtracting(prefetched).compactMap { element(for: $0) }

        prefetched = next

        if cancelled.isNotEmpty {
            configuration.onCancelPrefetchingElements(cancelled)
        }
        if added.isNotEmpty {
            configuration.onPrefetchingElements(added)
        }
    }

    private func cancelPrefetch() {
        let cancelled = prefetched.compactMap { element(for: $0) }
        prefetched.removeAll()
        if cancelled.isNotEmpty {
            configuration.onCancelPrefetchingElements(cancelled)
        }
    }

    func disconnect() {
        disconnected = true
        settleWork?.cancel()
        cancelScrollAnimation()
        cancelPrefetch()

        if configuration.proxy.collectionView === self {
            configuration.proxy.collectionView = nil
        }
    }
}
#endif
