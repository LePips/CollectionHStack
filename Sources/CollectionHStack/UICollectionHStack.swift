#if canImport(UIKit)
import SwiftUI

// UIKit supplies reuse, focus, and animated updates. Measurement is cached separately
// so SwiftUI proposals do not overwrite the collection's live layout during resizing.

// MARK: UICollectionHStack

private let cellReuseIdentifier = "HostingCollectionViewCell"
private let alignedLeadingElementIDUpdateDelay: TimeInterval = 0.05

public protocol _UICollectionHStack: UIView {

    func scrollTo(index: Int, animated: Bool)
    func snapshotReload()

    /// Returns the index of the given element if its
    /// `id` exists in the current `UICollectionHStack`
    func index(id: some Hashable) -> Int?
}

public class UICollectionHStack<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
>:
    UIView,
    _UICollectionHStack,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout,
    CollectionHStackItemSizeProvider,
    UICollectionViewDataSourcePrefetching
    where Data.Element == Element, Data.Index == Int
{

    private var identifier: (Element) -> ID
    private var dataIndex = CollectionDataIndex<ID>()
    // Structural updates retain base identities and optional survivor offsets only.
    private var stagedItems: CollectionSnapshot<ID>?
    private var dataTransition: CollectionDataTransition<Data, ID>?

    // binding
    private var alignedLeadingElementID: Binding<ID?>?
    private let alignedLeadingElementUpdate = CollectionDeferredUpdate()
    private var dataUpdateGeneration = 0
    private var isDataUpdateInProgress = false

    // events
    private var onReachedLeadingEdge: () -> Void
    private var onReachedLeadingEdgeOffset: CollectionHStackEdgeOffset
    private var onReachedTrailingEdge: () -> Void
    private var onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset
    private var onPrefetchingElements: ([Element]) -> Void
    private var onCancelPrefetchingElements: ([Element]) -> Void

    // internal
    private var effectiveItemCount: Int
    private var isCarousel: Bool
    private var data: Data
    private var insets: EdgeInsets
    private var itemSpacing: CGFloat
    private var itemMeasurementRevision = 0
    private let itemSizing = CollectionItemSizing<Content>()
    private var itemSize: CGSize?
    private var layout: CollectionHStackLayout
    private var onReachedEdgeStore: Set<Edge>
    private var scrollBehavior: CollectionHStackScrollBehavior
    private var initialElementID: ID?
    private var hasEvaluatedInitialElement = false
    private var pendingInitialElementID: ID?
    private var fittingSizeCache: (width: CGFloat, selfSize: CGSize, itemSize: CGSize)?
    private var resizeTransition = CollectionResizeTransition()
    private var lastLaidOutWidth: CGFloat?
    private var needsSizingUpdate = true
    private var renderingInsets: UIEdgeInsets = .zero
    private var size = CGSize(width: UIView.noIntrinsicMetric, height: 0)
    private var variadicItemSizeCache: [ID: CGSize] = [:]

    // resizing
    private let contentRefresh = CollectionContentRefresh()
    /// Unlike `lastLaidOutWidth`, this survives sizing invalidation so a remeasured
    /// layout still preserves the scroll position of the one it replaces.
    private var lastAppliedWidth: CGFloat?
    private var scrollAnchor: CollectionScrollAnchor?
    private var isAdjustingScrollPosition = false
    private var isLayoutDeferred = false
    private var isForcingLayout = false
    private var visibilityObservations: [NSKeyValueObservation] = []

    // MARK: view provider

    private var contentEnvironment: EnvironmentValues?
    private var measurementEnvironment: ContentMeasurementEnvironment?
    private var needsEnvironmentContentRefresh = false
    private var viewProvider: (Element) -> Content

    // MARK: init

    init(
        id: KeyPath<Element, ID>,
        alignedLeadingElementID: Binding<ID?>?,
        clipsToBounds: Bool,
        data: Data,
        dataPrefix: Int?,
        insets: EdgeInsets,
        isCarousel: Bool,
        itemSpacing: CGFloat,
        layout: CollectionHStackLayout,
        onReachedLeadingEdge: @escaping () -> Void,
        onReachedLeadingEdgeOffset: CollectionHStackEdgeOffset,
        onReachedTrailingEdge: @escaping () -> Void,
        onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset,
        onPrefetchingElements: @escaping ([Element]) -> Void,
        onCancelPrefetchingElements: @escaping ([Element]) -> Void,
        proxy: CollectionHStackProxy,
        scrollBehavior: CollectionHStackScrollBehavior,
        initialElementID: ID? = nil,
        viewProvider: @escaping (Element) -> Content
    ) {
        self.identifier = { $0[keyPath: id] }
        self.alignedLeadingElementID = alignedLeadingElementID
        self.data = data
        self.effectiveItemCount = 0
        self.insets = insets
        self.isCarousel = isCarousel
        self.itemSpacing = itemSpacing
        self.layout = layout
        self.onReachedLeadingEdge = onReachedLeadingEdge
        self.onReachedLeadingEdgeOffset = onReachedLeadingEdgeOffset
        self.onReachedTrailingEdge = onReachedTrailingEdge
        self.onReachedTrailingEdgeOffset = onReachedTrailingEdgeOffset
        self.onPrefetchingElements = onPrefetchingElements
        self.onCancelPrefetchingElements = onCancelPrefetchingElements
        self.onReachedEdgeStore = []
        self.scrollBehavior = scrollBehavior
        self.initialElementID = initialElementID
        self.viewProvider = viewProvider

        super.init(frame: .zero)

        dataIndex.update(from: data, id: id, prefix: dataPrefix)
        effectiveItemCount = itemCount(for: dataIndex)
        evaluateInitialElementIfNeeded()

        proxy.collectionView = self

        collectionView.clipsToBounds = clipsToBounds

        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self,
            UITraitDisplayScale.self,
        ]) { (self: Self, _: UITraitCollection) in
            self.invalidateSizing()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        size
    }

    override public var bounds: CGRect {
        didSet {
            if bounds.size != oldValue.size {
                updateSizes(forWidth: bounds.width)
            }
        }
    }

    override public var frame: CGRect {
        didSet {
            if frame.size != oldValue.size {
                updateSizes(forWidth: bounds.width)
            }
            if frame.origin != oldValue.origin {
                setNeedsLayout()
            }
        }
    }

    // MARK: collectionView

    private lazy var collectionView: UICollectionView = {

        let layout = scrollBehavior.flowLayout
        layout.scrollDirection = .horizontal
        layout.sectionInset = .init(
            top: insets.top,
            left: insets.leading,
            bottom: insets.bottom,
            right: insets.trailing
        )
        layout.minimumLineSpacing = nonnegativeFinite(itemSpacing)
        layout.minimumInteritemSpacing = nonnegativeFinite(itemSpacing)

        #if os(tvOS)
        let collectionView = FocusCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.identityAt = { [weak self] path in
            guard let self, path.section == 0, (0 ..< self.effectiveItemCount).contains(path.item) else { return nil }

            return AnyHashable(self.item(at: path.item).identity)
        }
        collectionView.indexPathForIdentity = { [weak self] identity in
            guard let self, let identity = identity.base as? CollectionItem<ID>.Identity else { return nil }

            if let stagedItems = self.stagedItems {
                return stagedItems.firstIndex { $0.identity == identity }.map { IndexPath(item: $0, section: 0) }
            }
            guard let offset = self.dataIndex.ids.firstIndex(of: identity.id) else { return nil }

            let position = identity.repetition * self.dataIndex.ids.count + offset
            // If a carousel repetition disappeared, restore the surviving element.
            return IndexPath(item: position < self.effectiveItemCount ? position : offset, section: 0)
        }
        #else
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        #endif
        collectionView.register(
            HostingCollectionViewCell<Content>.self,
            forCellWithReuseIdentifier: cellReuseIdentifier
        )
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = nil
        collectionView.bounces = true
        collectionView.alwaysBounceHorizontal = true

        if scrollBehavior == .columnPaging || scrollBehavior == .fullPaging {
            collectionView.decelerationRate = .fast
        }

        addSubview(collectionView)

        return collectionView
    }()

    // MARK: layoutSubviews

    override public func layoutSubviews() {
        // Update both metrics and bounds before UIKit lays out the child. Otherwise
        // shrinking a window briefly lays out the old, taller items in the new height.
        updateSizes(forWidth: bounds.width)
        if !isLayoutDeferred {
            collectionView.frame = renderingFrame
        }
        super.layoutSubviews()
        guard !isLayoutDeferred else { return }

        refreshContentIfSettled()
        applyInitialElementIfNeeded()
        scheduleAlignedLeadingElementIDUpdate()
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        stopObservingVisibility()
        if isLayoutDeferred, window != nil {
            observeVisibility()
            applyDeferredLayoutIfVisible()
        }
    }

    // MARK: offscreen deferral

    /// Rows of a vertically scrolling stack outside the window still receive every
    /// resize. They keep reporting the correct height to SwiftUI, but postpone native
    /// layout, and therefore resizing their hosted cells, until they scroll into view
    /// or the window grows to reveal them. Both apply the layout before the frame is
    /// rendered. Rows displaced horizontally, as during navigation transitions, lay out
    /// immediately, as do rows on focus-driven platforms so focus can reach any row.
    private var shouldDeferLayout: Bool {
        #if os(iOS)
        guard !isForcingLayout, lastAppliedWidth != nil, pendingInitialElementID == nil, !isDataUpdateInProgress,
              let window else { return false }

        let frame = convert(bounds, to: window)
        return frame.maxY < window.bounds.minY || frame.minY > window.bounds.maxY
        #else
        false
        #endif
    }

    private func observeVisibility() {
        guard visibilityObservations.isEmpty else { return }

        let applyIfVisible: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                self?.applyDeferredLayoutIfVisible()
            }
        }
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                visibilityObservations.append(scrollView.observe(\.contentOffset) { _, _ in applyIfVisible() })
            }
            ancestor = view.superview
        }
        if let scene = window?.windowScene {
            // The window and its content may resize after the scene reports new geometry.
            visibilityObservations.append(scene.observe(\.effectiveGeometry) { _, _ in
                applyIfVisible()
                DispatchQueue.main.async(execute: applyIfVisible)
            })
        }
    }

    private func stopObservingVisibility() {
        visibilityObservations.forEach { $0.invalidate() }
        visibilityObservations.removeAll()
    }

    private func applyDeferredLayoutIfVisible() {
        guard isLayoutDeferred, !shouldDeferLayout else { return }

        applyDeferredLayout()
    }

    /// Lays out immediately, for example before scrolling to an item.
    private func applyDeferredLayout() {
        guard isLayoutDeferred else { return }

        isForcingLayout = true
        defer { isForcingLayout = false }
        setNeedsLayout()
        layoutIfNeeded()
        // The resize that deferred this layout has finished; show current content.
        refreshVisibleItems()
    }

    private func evaluateInitialElementIfNeeded() {
        guard !hasEvaluatedInitialElement, let initialElementID, dataIndex.ids.isNotEmpty else { return }

        hasEvaluatedInitialElement = true
        pendingInitialElementID = dataIndex.ids.contains(initialElementID) ? initialElementID : nil
        if pendingInitialElementID != nil {
            setNeedsLayout()
        }
    }

    private func applyInitialElementIfNeeded() {
        guard let target = pendingInitialElementID,
              collectionView.bounds.width.isFiniteAndPositive,
              collectionView.bounds.height.isFiniteAndPositive else { return }

        // Consume before scrolling, which can synchronously trigger another layout.
        pendingInitialElementID = nil
        guard let index = index(id: target) else { return }

        UIView.performWithoutAnimation {
            scrollTo(index: index, animated: false)
            (collectionView.flowLayout as? FullPagingFlowLayout)?.synchronizePageWithContentOffset()
        }
    }

    func prepareForLayout() {
        resizeTransition.prepareForLayout()
    }

    func fittingSize(forProposedWidth width: CGFloat) -> CGSize {
        guard width.isFiniteAndPositive else { return fittingSize(forWidth: width) }

        if resizeTransition.propose(
            width: width, displayedWidth: bounds.width,
            displayedItemSize: itemSize ?? collectionView.flowLayout.itemSize,
            displayedHeight: size.height, pixel: pixelAlignmentDistance,
            targetItemWidth: layoutMetrics.itemWidth(for: width)
        ) {
            fittingSizeCache = nil
        }
        return fittingSize(forWidth: width)
    }

    private var pixelAlignmentDistance: CGFloat {
        1 / max(traitCollection.displayScale, 1)
    }

    func fittingSize(forWidth width: CGFloat) -> CGSize {
        guard width.isFiniteAndPositive else {
            return CGSize(width: max(width, 0), height: size.height)
        }

        if let fittingSizeCache, fittingSizeCache.width == width {
            return CGSize(width: width, height: fittingSizeCache.selfSize.height)
        }

        let resolvedSizes = computeSizes(forWidth: width)
        fittingSizeCache = (width, resolvedSizes.selfSize, resolvedSizes.itemSize)

        return CGSize(width: width, height: resolvedSizes.selfSize.height)
    }

    private func updateSizes(forWidth width: CGFloat) {
        resizeTransition.apply(width: width, pixel: pixelAlignmentDistance)
        let newRenderingInsets = visibleOverflowInsets
        let viewportChanged = renderingInsets != newRenderingInsets
        let needsLayout = width.isFiniteAndPositive && (needsSizingUpdate || lastLaidOutWidth != width || viewportChanged)
        if needsLayout, shouldDeferLayout {
            if !isLayoutDeferred {
                isLayoutDeferred = true
                observeVisibility()
            }
            return
        }
        // A deferred row may also return to its laid-out width before it is visible.
        if isLayoutDeferred {
            isLayoutDeferred = false
            stopObservingVisibility()
        }
        guard needsLayout else { return }

        applySizes(forWidth: width, renderingInsets: newRenderingInsets, viewportChanged: viewportChanged)
    }

    private func applySizes(forWidth width: CGFloat, renderingInsets newRenderingInsets: UIEdgeInsets, viewportChanged: Bool) {
        let resolvedSizes: (selfSize: CGSize, itemSize: CGSize) = if let fittingSizeCache, fittingSizeCache.width == width {
            (fittingSizeCache.selfSize, fittingSizeCache.itemSize)
        } else {
            computeSizes(forWidth: width)
        }

        let newSelfSize = resolvedSizes.selfSize
        let newItemSize = resolvedSizes.itemSize
        let itemSizeChanged = itemSize != newItemSize
        let intrinsicHeightChanged = size.height != newSelfSize.height

        // Record the position against the outgoing layout, before any metrics change.
        // Rendering insets alone preserve positions through balanced section insets.
        if let previousWidth = lastAppliedWidth, previousWidth != width || itemSizeChanged {
            scrollAnchor = scrollAnchor ?? currentScrollAnchor()
            if previousWidth != width {
                contentRefresh.geometryChanged()
            }
        }
        isAdjustingScrollPosition = true
        defer { isAdjustingScrollPosition = false }

        lastLaidOutWidth = width
        lastAppliedWidth = width
        needsSizingUpdate = false
        itemSize = newItemSize
        size = newSelfSize
        renderingInsets = newRenderingInsets
        (collectionView.flowLayout as? CollectionHStackFlowLayout)?.renderingInsets = renderingInsets
        if collectionView.flowLayout.sectionInset != collectionSectionInsets {
            collectionView.flowLayout.sectionInset = collectionSectionInsets
        }
        // UIKit can round to the destination's pixel width while SwiftUI is
        // still proposing fractional widths in the animation's settling tail.
        // Keep the transition until its destination or configuration changes.

        if itemSizeChanged, case .selfSizingVariadicWidth = layout {
            // Variadic layouts continue to resolve each item through the delegate.
        } else if itemSizeChanged {
            // Keep UICollectionViewFlowLayout's cached metrics in sync immediately.
            // During iPad window transitions, invalidating delegate metrics alone can
            // leave its itemSize and existing attributes at the pre-transition width.
            collectionView.flowLayout.itemSize = newItemSize
        }

        // Invalidate cached attributes before changing the child frame, which can
        // synchronously trigger layout during a shrinking window transition.
        if itemSizeChanged || viewportChanged {
            collectionView.collectionViewLayout.invalidateLayout()
        }
        collectionView.frame = renderingFrame

        if intrinsicHeightChanged {
            invalidateIntrinsicContentSize()
        }
        // The parent supplies intermediate frames during an animated resize,
        // so UIKit can coalesce those layouts. Initial layout, direct UIKit sizing,
        // scroll targets and the final frame still need attributes immediately.
        let requiresImmediateLayout = resizeTransition.current == nil || window == nil
            || width == resizeTransition.current?.targetWidth || pendingInitialElementID != nil
        // Position the reflowed content before laying out cells, so cells are
        // laid out once, at their final offset.
        if let scrollAnchor {
            restoreScrollPosition(to: scrollAnchor)
        }
        if (itemSizeChanged || viewportChanged) && requiresImmediateLayout {
            collectionView.layoutIfNeeded()
        }
    }

    // MARK: scroll anchoring

    /// Content offsets the collection can rest at, including adjusted content insets.
    private var scrollRange: ClosedRange<CGFloat> {
        scrollRange(contentWidth: collectionView.contentSize.width)
    }

    private func scrollRange(contentWidth: CGFloat) -> ClosedRange<CGFloat> {
        let minimum = -collectionView.adjustedContentInset.left
        let maximum = contentWidth + collectionView.adjustedContentInset.right - collectionView.bounds.width
        return minimum ... max(minimum, maximum)
    }

    /// Leading-aligned behaviors keep their leading column, continuous scrolling keeps
    /// the item at the viewport's center, and full paging keeps its page.
    private func currentScrollAnchor() -> CollectionScrollAnchor? {
        guard effectiveItemCount > 0, collectionView.bounds.width.isFiniteAndPositive,
              let flowLayout = collectionView.flowLayout as? CollectionHStackFlowLayout else { return nil }

        let offset = collectionView.contentOffset.x
        let range = scrollRange
        if offset <= range.lowerBound + 0.5 {
            return .leading
        }
        if offset >= range.upperBound - 0.5 {
            return .trailing
        }
        if let paging = flowLayout as? FullPagingFlowLayout {
            return paging.pageSize.isFiniteAndPositive ? .page((offset / paging.pageSize).rounded()) : nil
        }

        let centered = scrollBehavior == .continuous
        let viewport = flowLayout.viewportBounds(at: collectionView.contentOffset)
        let reference = centered ? viewport.midX : offset + flowLayout.sectionInset.left
        let nearest = flowLayout.layoutAttributesForElements(in: viewport)?
            .filter { $0.representedElementCategory == .cell && $0.frame.width.isFiniteAndPositive }
            .min {
                abs((centered ? $0.frame.midX : $0.frame.minX) - reference) < abs((centered ? $1.frame.midX : $1.frame.minX) - reference)
            }
        guard let nearest else { return nil }

        return .item(index: nearest.indexPath.item, fraction: (reference - nearest.frame.minX) / nearest.frame.width, centered: centered)
    }

    /// Queries go through the collection view, which prepares an invalidated layout
    /// without laying out cells, so the new offset can be applied first.
    private func restoreScrollPosition(to anchor: CollectionScrollAnchor) {
        // Never move content out from under the user's finger or momentum.
        guard !collectionView.isTracking, !collectionView.isDecelerating, !isDataUpdateInProgress, effectiveItemCount > 0,
              let flowLayout = collectionView.flowLayout as? CollectionHStackFlowLayout else { return }

        let target: CGFloat
        switch anchor {
        case .leading:
            target = scrollRange.lowerBound

        case .trailing:
            _ = collectionView.layoutAttributesForItem(at: IndexPath(item: effectiveItemCount - 1, section: 0))
            target = .greatestFiniteMagnitude

        case let .page(page):
            guard let paging = flowLayout as? FullPagingFlowLayout else { return }

            _ = collectionView.layoutAttributesForItem(at: IndexPath(item: effectiveItemCount - 1, section: 0))
            target = page * paging.pageSize

        case let .item(index, fraction, centered):
            guard index < effectiveItemCount,
                  let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { return }

            let reference = centered ? flowLayout.viewportBounds(at: .zero).midX : flowLayout.sectionInset.left
            target = attributes.frame.minX + attributes.frame.width * fraction - reference
        }

        // The prepared layout's content size is current before the collection lays out.
        let offset = target.clamped(to: scrollRange(contentWidth: flowLayout.collectionViewContentSize.width))
        guard abs(offset - collectionView.contentOffset.x) > 0.001 else { return }

        collectionView.contentOffset.x = offset
    }

    private var collectionSectionInsets: UIEdgeInsets {
        .init(
            top: insets.top,
            left: insets.leading + renderingInsets.left,
            bottom: insets.bottom,
            right: insets.trailing + renderingInsets.right
        )
    }

    private var renderingFrame: CGRect {
        // A parent can animate width and height independently. Packing uses the
        // measured height for the committed width so a wrapped caption cannot
        // temporarily push a configured row into another column.
        CGRect(origin: bounds.origin, size: CGSize(width: bounds.width, height: size.height))
            .inset(by: .init(top: 0, left: -renderingInsets.left, bottom: 0, right: -renderingInsets.right))
    }

    private var visibleOverflowInsets: UIEdgeInsets {
        // UIKit recycles cells outside its bounds even with clipping disabled.
        // Rows that manage their own insets can expand the rendering viewport,
        // balancing section insets so sizing and scroll offsets stay unchanged.
        guard !collectionView.clipsToBounds, collectionView.contentInsetAdjustmentBehavior == .never,
              let window else { return .zero }

        let windowBounds = convert(window.bounds, from: window)
        var left = windowBounds.minX
        var right = windowBounds.maxX
        var ancestor = superview
        while let view = ancestor {
            if view.clipsToBounds {
                let visibleBounds = convert(view.bounds, from: view)
                left = max(left, visibleBounds.minX)
                right = min(right, visibleBounds.maxX)
            }
            ancestor = view.superview
        }
        guard right > left else { return .zero }

        return .init(top: 0, left: max(0, bounds.minX - left), bottom: 0, right: max(0, right - bounds.maxX))
    }

    func updateEnvironment(_ environment: EnvironmentValues) {
        let signature = ContentMeasurementEnvironment(environment)
        let measurementChanged = measurementEnvironment != signature
        measurementEnvironment = signature
        contentEnvironment = environment
        if measurementChanged {
            invalidateSizing()
            // Display changed typography in the same pass as its new metrics.
            needsEnvironmentContentRefresh = true
        }
    }

    private func invalidateSizing(keepingMeasurements: Bool = false) {
        needsSizingUpdate = true
        fittingSizeCache = nil
        resizeTransition = CollectionResizeTransition()
        lastLaidOutWidth = nil
        itemSize = nil
        if !keepingMeasurements {
            itemSizing.invalidate()
            variadicItemSizeCache.removeAll(keepingCapacity: true)
        }

        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    // MARK: content refresh

    /// Supplies the latest views to visible cells that predate the current content generation.
    private func refreshVisibleItems() {
        contentRefresh.didRefresh()
        for path in collectionView.indexPathsForVisibleItems {
            guard (0 ..< effectiveItemCount).contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? HostingCollectionViewCell<Content>,
                  cell.contentGeneration != contentRefresh.generation else { continue }

            configure(cell, at: path.item)
        }
    }

    /// Containers that adapt to their width update every row on each resize frame,
    /// usually without changing any item content. Visible cells are already laid out
    /// again at their new size, so refreshing their content as well would rebuild
    /// every hosted view each frame. Defer it until the width settles; cells that
    /// appear meanwhile are configured with the latest content as usual.
    private func refreshContentIfSettled() {
        contentRefresh.refreshIfSettled(isAttached: window != nil) { [weak self] in
            self?.refreshVisibleItems()
        }
    }

    // MARK: proxy

    public func snapshotReload() {
        invalidateSizing()

        guard let snapshot = collectionView.snapshotView(afterScreenUpdates: false) else {
            collectionView.reloadData()
            scheduleAlignedLeadingElementIDUpdate()
            return
        }

        addSubview(snapshot)
        snapshot.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            snapshot.topAnchor.constraint(equalTo: collectionView.topAnchor),
            snapshot.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
            snapshot.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            snapshot.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
        ])

        collectionView.alpha = 0
        collectionView.reloadData()
        scheduleAlignedLeadingElementIDUpdate()

        UIView.animate(withDuration: 0.1) {
            snapshot.alpha = 0
            self.collectionView.alpha = 1
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }

    public func scrollTo(index: Int, animated: Bool) {

        guard (0 ..< effectiveItemCount).contains(index) else { return }

        applyDeferredLayout()
        collectionView.layoutIfNeeded()
        if collectionView.flowLayout is ColumnAlignedLayout,
           let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        {
            let maximum = max(0, collectionView.contentSize.width - collectionView.bounds.width)
            let offset = (attributes.frame.minX - collectionView.flowLayout.sectionInset.left).clamped(to: 0 ... maximum)
            collectionView.setContentOffset(CGPoint(x: offset, y: 0), animated: animated)
        } else {
            let indexPath = IndexPath(row: index, section: 0)
            if renderingInsets == .zero {
                collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
            } else if let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) {
                let maximum = max(0, collectionView.contentSize.width - collectionView.bounds.width)
                let offset = (attributes.center.x - renderingInsets.left - bounds.width / 2).clamped(to: 0 ... maximum)
                collectionView.setContentOffset(CGPoint(x: offset, y: 0), animated: animated)
            }
        }

        // Animated scrolling emits did-scroll callbacks which keep postponing this
        // publication until the content offset stops changing.
        scheduleAlignedLeadingElementIDUpdate(after: animated ? alignedLeadingElementIDUpdateDelay : 0)
    }

    public func index(id: some Hashable) -> Int? {
        if let stagedItems {
            return stagedItems.firstIndex { AnyHashable($0.id) == AnyHashable(id) }
        }
        return dataIndex.ids.firstIndex { AnyHashable($0) == AnyHashable(id) }
    }

    /// Computes a stable item size from the supplied width rather than reading `bounds`
    /// throughout the calculation. This makes SwiftUI's proposal and UIKit's layout pass
    /// agree on the same height during a resize.
    func computeSizes(forWidth availableWidth: CGFloat) -> (selfSize: CGSize, itemSize: CGSize) {
        guard availableWidth.isFiniteAndPositive else { return (.zero, .zero) }

        let metrics = layoutMetrics
        let rows = metrics.rows
        let singleItemSize: CGSize = if let transition = resizeTransition.current, let progress = transition.progress(for: availableWidth) {
            // Measure intermediate widths so caption wrapping remains accurate.
            measuredItemSize(width: transition.itemWidth(at: progress), reusingContent: true)
        } else {
            measuredItemSize(width: metrics.itemWidth(for: availableWidth))
        }

        if let alignedLayout = collectionView.flowLayout as? ColumnAlignedLayout {
            alignedLayout.rows = rows
        }

        // SwiftUI aligns the representable's height to physical pixels. Round up
        // first so that alignment cannot make the row shorter than its items.
        // Ignore one floating-point step of measurement noise at pixel boundaries.
        let displayScale = max(traitCollection.displayScale, 1)
        let height = (metrics.height(for: singleItemSize).nextDown * displayScale).rounded(.up) / displayScale
        var flowLayoutItemSize = singleItemSize

        // Flow layout uses strict fits when packing rows. Rounding the total height
        // can leave multiple rows one floating-point step too tall, making UIKit
        // unexpectedly place them in separate columns during a subpoint resize.
        // Keep all rows inside the rounded viewport without changing rendered pixels.
        if flowLayoutItemSize.height > 0 {
            let availableHeight = max(0, height - insets.top - insets.bottom - CGFloat(rows - 1) * metrics.spacing)
            flowLayoutItemSize.height = min(flowLayoutItemSize.height, availableHeight / CGFloat(rows)).nextDown
        }

        return (
            CGSize(width: UIView.noIntrinsicMetric, height: max(height, 0)),
            CGSize(
                width: max(flowLayoutItemSize.width, 0),
                height: max(flowLayoutItemSize.height, 0)
            )
        )
    }

    private var layoutMetrics: LayoutMetrics {
        LayoutMetrics(layout: layout, insets: insets, itemSpacing: itemSpacing)
    }

    private var resolvedRows: Int {
        layoutMetrics.rows
    }

    private func measuredItemSize(width: CGFloat? = nil, reusingContent: Bool = false) -> CGSize {
        guard data.isNotEmpty else { return CGSize(width: nonnegativeFinite(width ?? 0), height: 0) }

        return itemSizing.size(width: width, environment: contentEnvironment, reusingContent: reusingContent) {
            let element = data[data.startIndex]
            return (viewProvider(element), AnyHashable(identifier(element)))
        }
    }

    private func contentSize(width: CGFloat?, element: Element) -> CGSize {
        itemSizing.measure(viewProvider(element), identity: AnyHashable(identifier(element)), width: width, environment: contentEnvironment)
    }

    private func configure(_ cell: HostingCollectionViewCell<Content>, at position: Int) {
        cell.setup(
            view: viewProvider(element(at: position)),
            id: AnyHashable(item(at: position).identity),
            generation: contentRefresh.generation,
            environment: contentEnvironment
        )
    }

    private func itemCount(for index: CollectionDataIndex<ID>) -> Int {
        guard index.ids.isNotEmpty else { return 0 }

        return isCarousel ? max(100, effectiveItemCount, index.ids.count) : index.ids.count
    }

    private func item(at index: Int) -> CollectionItem<ID> {
        if let stagedItems {
            return stagedItems[index]
        }
        return dataIndex.item(at: index)
    }

    private func element(at position: Int) -> Element {
        if let stagedItems, let dataTransition {
            return dataTransition.element(for: stagedItems[position].id, in: data, index: dataIndex)
        }
        return dataIndex.element(in: data, at: position)
    }

    func configure(_ configuration: CollectionHStack<Element, Data, ID, Content>) {
        identifier = configuration.identifier
        if collectionView.contentInsetAdjustmentBehavior != configuration.contentInsetAdjustmentBehavior {
            collectionView.contentInsetAdjustmentBehavior = configuration.contentInsetAdjustmentBehavior
        }
        #if os(tvOS)
        (collectionView as? FocusCollectionView)?.behavior = configuration.focusBehavior
        #endif
        onReachedLeadingEdge = configuration.onReachedLeadingEdge
        onReachedLeadingEdgeOffset = configuration.onReachedLeadingEdgeOffset
        onReachedTrailingEdge = configuration.onReachedTrailingEdge
        onReachedTrailingEdgeOffset = configuration.onReachedTrailingEdgeOffset
        onPrefetchingElements = configuration.onPrefetchingElements
        onCancelPrefetchingElements = configuration.onCancelPrefetchingElements
        isCarousel = configuration.isCarousel
        if initialElementID != configuration.initialElementID {
            initialElementID = configuration.initialElementID
            hasEvaluatedInitialElement = false
            pendingInitialElementID = nil
        }
        collectionView.clipsToBounds = configuration.clipsToBounds
        setNeedsLayout()
        configuration.proxy.collectionView = self
        if scrollBehavior != configuration.scrollBehavior {
            scrollBehavior = configuration.scrollBehavior
            let flowLayout = scrollBehavior.flowLayout
            flowLayout.scrollDirection = .horizontal
            collectionView.setCollectionViewLayout(flowLayout, animated: false)
            collectionView.decelerationRate = scrollBehavior == .columnPaging || scrollBehavior == .fullPaging ? .fast : .normal
            invalidateSizing()
        }
    }

    // MARK: - Update

    func update(
        newData: Data,
        alignedLeadingElementID: Binding<ID?>?,
        allowBouncing: Bool? = nil,
        allowScrolling: Bool? = nil,
        dataPrefix: Int? = nil,
        layout newLayout: CollectionHStackLayout,
        insets newInsets: EdgeInsets? = nil,
        itemSpacing newItemSpacing: CGFloat? = nil,
        itemMeasurementRevision: Int = 0,
        viewProvider: ((Element) -> Content)? = nil,
        defersContentRefresh: Bool = false
    ) {
        self.alignedLeadingElementID = alignedLeadingElementID
        let wasEmpty = data.isEmpty
        let insets = newInsets ?? self.insets
        let itemSpacing = newItemSpacing ?? self.itemSpacing
        let sizingConfigurationChanged = newLayout != layout
            || insets != self.insets || itemSpacing != self.itemSpacing
            || itemMeasurementRevision != self.itemMeasurementRevision
        let measurementConfigurationChanged = newLayout != layout
            || insets.leading != self.insets.leading || insets.trailing != self.insets.trailing
            || itemSpacing != self.itemSpacing || itemMeasurementRevision != self.itemMeasurementRevision
        let verticalInsetsOnly = sizingConfigurationChanged && !measurementConfigurationChanged
        // Capture against the old row packing before section insets invalidate it.
        if sizingConfigurationChanged {
            scrollAnchor = scrollAnchor ?? currentScrollAnchor()
        }
        if verticalInsetsOnly {
            contentRefresh.geometryChanged()
        }

        let previouslyVariadic = usesVariadicWidths
        layout = newLayout
        if previouslyVariadic != usesVariadicWidths {
            // UICollectionView caches optional delegate capabilities on assignment.
            collectionView.delegate = nil
            collectionView.delegate = self
        }
        self.insets = insets
        self.itemSpacing = itemSpacing
        self.itemMeasurementRevision = itemMeasurementRevision
        if let viewProvider {
            self.viewProvider = viewProvider
        }
        // Flow layout setters invalidate the layout, so only apply changes.
        let flowLayout = collectionView.flowLayout
        let spacing = nonnegativeFinite(itemSpacing)
        if flowLayout.sectionInset != collectionSectionInsets {
            flowLayout.sectionInset = collectionSectionInsets
        }
        if flowLayout.minimumLineSpacing != spacing {
            flowLayout.minimumLineSpacing = spacing
        }
        if flowLayout.minimumInteritemSpacing != spacing {
            flowLayout.minimumInteritemSpacing = spacing
        }

        // data

        var newIndex = dataIndex
        var lookup: [ID: Int]?
        let changedIDs = newIndex.update(from: newData, identifier: identifier, prefix: dataPrefix, lookup: &lookup)
        let newCount = itemCount(for: newIndex)
        let hasDataChanges = changedIDs || newCount != effectiveItemCount

        if hasDataChanges {
            dataUpdateGeneration += 1
            let updateGeneration = dataUpdateGeneration
            isDataUpdateInProgress = true

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.dataUpdateGeneration == updateGeneration else { return }

                self.isDataUpdateInProgress = false
                self.scheduleAlignedLeadingElementIDUpdate()
            }

            // Inserting into a zero-size viewport can materialize the entire
            // data set for UIKit's update animation. Wait for usable geometry.
            if collectionView.window == nil || !collectionView.bounds.width.isFiniteAndPositive || !collectionView.bounds
                .height
                .isFiniteAndPositive
            {
                data = newData
                dataIndex = newIndex
                effectiveItemCount = newCount
                collectionView.reloadData()
            } else {
                let source = dataIndex.items(count: effectiveItemCount)
                let changes = CollectionDiff(
                    source: source,
                    target: newIndex.items(count: newCount),
                    lookup: lookup
                )

                dataTransition = CollectionDataTransition(
                    previousData: data,
                    previousIndex: dataIndex,
                    currentIndex: newIndex,
                    lookup: &lookup,
                    hasDeletions: !changes.deleted.isEmpty
                )
                stagedItems = source
                data = newData
                dataIndex = newIndex

                collectionView.apply(changes) { items in
                    self.stagedItems = items
                    self.effectiveItemCount = items.count
                }
                stagedItems = nil
                dataTransition = nil
            }
            scrollAnchor = nil
        } else {
            data = newData
            dataIndex = newIndex
        }
        evaluateInitialElementIfNeeded()

        // Every visible cell, including those configured during staged updates,
        // now predates the latest data and view provider. SwiftUI lays out the
        // representable before rendering, which lets resizes skip the refresh.
        contentRefresh.invalidate()
        if !defersContentRefresh || hasDataChanges || measurementConfigurationChanged || needsEnvironmentContentRefresh || window == nil {
            refreshVisibleItems()
        } else {
            setNeedsLayout()
        }
        needsEnvironmentContentRefresh = false

        // allowBouncing

        if let allowBouncing {
            collectionView.bounces = allowBouncing
        }

        // allowScrolling

        if let allowScrolling {
            collectionView.isScrollEnabled = allowScrolling
        }

        if sizingConfigurationChanged || hasDataChanges || wasEmpty != newData.isEmpty {
            invalidateSizing(keepingMeasurements: verticalInsetsOnly && !hasDataChanges)
        }

        if hasDataChanges {
            CATransaction.commit()
        }

        // Refresh even without structural changes when SwiftUI supplies a new Binding.
        scheduleAlignedLeadingElementIDUpdate()
    }

    // MARK: UICollectionViewDataSource

    public func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        effectiveItemCount
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: cellReuseIdentifier,
            for: indexPath
        ) as! HostingCollectionViewCell<Content>

        configure(cell, at: indexPath.item)

        return cell
    }

    // MARK: UICollectionViewDelegate

    /// Hosted controls receive focus, preserving their actions and focus effects.
    public func collectionView(
        _ collectionView: UICollectionView,
        canFocusItemAt indexPath: IndexPath
    ) -> Bool {
        false
    }

    private var usesVariadicWidths: Bool {
        if case .selfSizingVariadicWidth = layout {
            return true
        }
        return false
    }

    override public func responds(to selector: Selector!) -> Bool {
        if selector == #selector(UICollectionViewDelegateFlowLayout.collectionView(_:layout:sizeForItemAt:)) {
            return usesVariadicWidths
        }
        return super.responds(to: selector)
    }

    func uniformItemSize(in collectionView: UICollectionView) -> CGSize? {
        guard !usesVariadicWidths else { return nil }

        return self.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )
    }

    // MARK: UICollectionViewDelegateFlowLayout

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {

        let size: CGSize

        if case CollectionHStackLayout.selfSizingVariadicWidth = layout {
            guard data.isNotEmpty else { return .zero }

            let item = item(at: indexPath.item)
            let id = item.id

            if let cachedSize = variadicItemSizeCache[id] {
                size = cachedSize
            } else {
                let measuredSize = contentSize(width: nil, element: element(at: indexPath.item))
                variadicItemSizeCache[id] = measuredSize
                size = measuredSize
            }
        } else {
            // A size delegate must not force another collection layout while UIKit is resolving attributes.
            let width = collectionView.bounds.width - renderingInsets.left - renderingInsets.right
            size = lastLaidOutWidth == width ? itemSize ?? computeSizes(forWidth: width).itemSize
                : computeSizes(forWidth: width.positiveFinite(or: bounds.width)).itemSize
        }

        // UIKit can request metrics between the parent's resize and the child's
        // bounds update. Keep those temporary attributes inside the actual viewport
        // without replacing the measured size used when the transition finishes.
        let contentInsets = collectionView.adjustedContentInset
        let sectionInsets = collectionView.flowLayout.sectionInset
        let availableHeight = collectionView.bounds.height
            - contentInsets.top - contentInsets.bottom
            - sectionInsets.top - sectionInsets.bottom
        let height: CGFloat
        if availableHeight > 0, usesVariadicWidths {
            let rowHeight = max(0, availableHeight - CGFloat(resolvedRows - 1) * layoutMetrics.spacing) / CGFloat(resolvedRows)
            height = size.height <= rowHeight.nextUp
                ? min(size.height, rowHeight).nextDown
                : min(size.height, availableHeight.nextDown)
        } else {
            // Fit all configured rows despite floating-point packing noise.
            let rows = min(resolvedRows, max(effectiveItemCount, 1))
            let rowHeight = (availableHeight - CGFloat(rows - 1) * collectionView.flowLayout.minimumInteritemSpacing) / CGFloat(rows)
            height = rowHeight > 0 ? min(size.height, rowHeight.nextDown) : size.height
        }

        return CGSize(width: max(size.width, 0), height: max(height, 0))
    }

    // MARK: UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {

        // Any other movement establishes a new position to preserve on the next resize.
        if !isAdjustingScrollPosition {
            scrollAnchor = nil
        }

        // Keep programmatic scrolling settle-only too. User-driven scrolling is
        // additionally protected by the dragging/decelerating checks below.
        scheduleAlignedLeadingElementIDUpdate(after: alignedLeadingElementIDUpdateDelay)

        // leading edge
        handleReachedLeadingEdge(with: scrollView.contentOffset.x)

        // trailing edge
        if isCarousel {
            handleCarouselReachedTrailingEdge(with: scrollView.contentOffset.x)
        } else {
            handleReachedTrailingEdge(with: scrollView.contentOffset.x)
        }
    }

    private func handleReachedLeadingEdge(with contentOffset: CGFloat) {

        let reachedLeading: Bool

        switch onReachedLeadingEdgeOffset {
        case let .columns(columns):
            let minIndexPath = collectionView
                .indexPathsForVisibleItems
                .map(\.row)
                .min() ?? Int.max

            reachedLeading = minIndexPath != Int.max && minIndexPath / resolvedRows < columns

        case let .offset(offset):
            reachedLeading = contentOffset <= offset
        }

        if reachedLeading {
            if !onReachedEdgeStore.contains(.leading) {
                onReachedEdgeStore.insert(.leading)

                onReachedLeadingEdge()
            }
        } else {
            onReachedEdgeStore.remove(.leading)
        }
    }

    private func handleCarouselReachedTrailingEdge(with contentOffset: CGFloat) {

        let reachPosition = collectionView.contentSize.width - collectionView.bounds.width - bounds.width
        let reachedTrailing = contentOffset >= reachPosition

        if reachedTrailing, effectiveItemCount > 0, !isDataUpdateInProgress {
            effectiveItemCount += 100
            collectionView.reloadData()
        }
    }

    private func handleReachedTrailingEdge(with contentOffset: CGFloat) {

        let reachedTrailing: Bool

        switch onReachedTrailingEdgeOffset {
        case let .columns(columns):
            let maxIndexPath = collectionView
                .indexPathsForVisibleItems
                .map(\.row)
                .max() ?? Int.min

            let totalColumns = effectiveItemCount == 0 ? 0 : (effectiveItemCount - 1) / resolvedRows + 1
            reachedTrailing = maxIndexPath != Int.min && maxIndexPath / resolvedRows >= totalColumns - columns

        case let .offset(offset):
            let reachPosition = collectionView.contentSize.width - collectionView.bounds.width - offset
            reachedTrailing = contentOffset >= reachPosition
        }

        if reachedTrailing {
            if !onReachedEdgeStore.contains(.trailing) {
                onReachedEdgeStore.insert(.trailing)

                onReachedTrailingEdge()
            }
        } else {
            onReachedEdgeStore.remove(.trailing)
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleAlignedLeadingElementIDUpdate()
    }

    public func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate {
            scheduleAlignedLeadingElementIDUpdate()
        }
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scheduleAlignedLeadingElementIDUpdate()
    }

    // MARK: aligned leading element

    private func scheduleAlignedLeadingElementIDUpdate(
        after delay: TimeInterval = alignedLeadingElementIDUpdateDelay
    ) {

        guard alignedLeadingElementID != nil else {
            alignedLeadingElementUpdate.cancel()
            return
        }

        alignedLeadingElementUpdate.schedule(after: delay) { [weak self] in
            self?.updateAlignedLeadingElementID()
        }
    }

    private func updateAlignedLeadingElementID() {

        guard let alignedLeadingElementID, !collectionView.isDragging, !collectionView.isDecelerating,
              !isDataUpdateInProgress else { return }

        collectionView.layoutIfNeeded()

        let newID = alignedLeadingElementIDAtCurrentOffset()

        guard alignedLeadingElementID.wrappedValue != newID else { return }

        alignedLeadingElementID.wrappedValue = newID
    }

    private func alignedLeadingElementIDAtCurrentOffset() -> ID? {

        guard collectionView.flowLayout is ColumnAlignedLayout, effectiveItemCount > 0, data.isNotEmpty, collectionView.bounds.width > 0,
              collectionView.bounds.height > 0 else { return nil }

        let leadingEdge = collectionView.contentOffset.x + collectionView.flowLayout.sectionInset.left
        let displayScale = max(collectionView.traitCollection.displayScale, 1)
        let tolerance = 1 / displayScale

        let alignedIndexPath = collectionView.collectionViewLayout
            .layoutAttributesForElements(in: collectionView.bounds)?
            .filter { attributes in
                attributes.representedElementCategory == .cell
                    && abs(attributes.frame.minX - leadingEdge) <= tolerance
            }
            .map(\.indexPath)
            .min { lhs, rhs in
                lhs.item < rhs.item
            }

        guard let alignedIndexPath, alignedIndexPath.item < effectiveItemCount else { return nil }

        return item(at: alignedIndexPath.item).id
    }

    // MARK: UICollectionViewDataSourcePrefetching

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let prefetchingElements = indexPaths.compactMap { path -> Element? in
            guard (0 ..< effectiveItemCount).contains(path.item) else { return nil }

            return element(at: path.item)
        }
        onPrefetchingElements(prefetchingElements)
    }

    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let cancellingElements = indexPaths.compactMap { path -> Element? in
            guard (0 ..< effectiveItemCount).contains(path.item) else { return nil }

            return element(at: path.item)
        }
        onCancelPrefetchingElements(cancellingElements)
    }
}

#endif
