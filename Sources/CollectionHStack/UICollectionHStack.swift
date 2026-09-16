#if canImport(UIKit)
import DifferenceKit
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
    UICollectionViewDataSourcePrefetching
    where Data.Element == Element, Data.Index == Int
{

    private var _id: KeyPath<Element, ID>
    private var dataIndex = CollectionDataIndex<ID>()
    // DifferenceKit needs materialized identities only while applying structural changes.
    private var stagedItems: [CollectionItem<ID>]?
    private var dataTransition: CollectionDataTransition<Data, ID>?

    // binding
    private var alignedLeadingElementID: Binding<ID?>?
    private var alignedLeadingElementIDUpdateGeneration = 0
    private var dataUpdateGeneration = 0
    private var isDataUpdateInProgress = false

    // events
    private var didScrollToItems: ([Element]) -> Void
    private var onReachedLeadingEdge: () -> Void
    private var onReachedLeadingEdgeOffset: CollectionHStackEdgeOffset
    private var onReachedTrailingEdge: () -> Void
    private var onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset
    private var onPrefetchingElements: ([Element]) -> Void
    private var onCancelPrefetchingElements: ([Element]) -> Void

    // internal
    private var dataPrefix: Int?
    private var effectiveItemCount: Int
    private var isCarousel: Bool
    private var data: Data
    private var insets: EdgeInsets
    private var itemSpacing: CGFloat
    private var itemSizeCache = ItemSizeCache()
    private var itemSize: CGSize?
    private var layout: CollectionHStackLayout
    private var onReachedEdgeStore: Set<Edge>
    private var scrollBehavior: CollectionHStackScrollBehavior
    private var initialElementID: ID?
    private var hasEvaluatedInitialElement = false
    private var pendingInitialElementID: ID?
    private var fittingSizeCache: (width: CGFloat, selfSize: CGSize, itemSize: CGSize)?
    private var lastLaidOutWidth: CGFloat?
    private var layoutInvalidationGeneration = 0
    private var needsSizingUpdate = true
    private var size = CGSize(width: UIView.noIntrinsicMetric, height: 0)
    private var variadicItemSizeCache: [ID: CGSize] = [:]

    // MARK: view provider

    private var viewProvider: (Element) -> Content

    // MARK: init

    init(
        id: KeyPath<Element, ID>,
        alignedLeadingElementID: Binding<ID?>?,
        clipsToBounds: Bool,
        data: Data,
        dataPrefix: Int?,
        didScrollToItems: @escaping ([Element]) -> Void,
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
        self._id = id
        self.alignedLeadingElementID = alignedLeadingElementID
        self.data = data
        self.dataPrefix = dataPrefix
        self.didScrollToItems = didScrollToItems
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

        dataIndex.update(from: data, id: _id, prefix: dataPrefix)
        effectiveItemCount = itemCount(for: dataIndex)
        evaluateInitialElementIfNeeded()

        proxy.collectionView = self

        collectionView.clipsToBounds = clipsToBounds
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
        }
    }

    // MARK: collectionView

    private lazy var collectionView: UICollectionView = {

        let layout = scrollBehavior.flowLayout
        layout.scrollDirection = .horizontal
        layout.sectionInset = .init(
            top: 0,
            left: insets.leading,
            bottom: 0,
            right: insets.trailing
        )
        layout.minimumLineSpacing = nonnegativeFinite(itemSpacing)
        layout.minimumInteritemSpacing = nonnegativeFinite(itemSpacing)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
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

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        return collectionView
    }()

    // MARK: layoutSubviews

    override public func layoutSubviews() {
        // Update both metrics and bounds before UIKit lays out the child. Otherwise
        // shrinking a window briefly lays out the old, taller items in the new height.
        updateSizes(forWidth: bounds.width)
        super.layoutSubviews()
        applyInitialElementIfNeeded()
        scheduleAlignedLeadingElementIDUpdate()
    }

    private func evaluateInitialElementIfNeeded() {
        guard !hasEvaluatedInitialElement, let initialElementID, dataIndex.ids.isNotEmpty else { return }
        hasEvaluatedInitialElement = true
        print(initialElementID)
        pendingInitialElementID = dataIndex[initialElementID] != nil ? initialElementID : nil
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

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            invalidateSizing()
        }
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
        guard width.isFiniteAndPositive else { return }
        guard needsSizingUpdate || lastLaidOutWidth != width else { return }

        let resolvedSizes: (selfSize: CGSize, itemSize: CGSize) = if let fittingSizeCache, fittingSizeCache.width == width {
            (fittingSizeCache.selfSize, fittingSizeCache.itemSize)
        } else {
            computeSizes(forWidth: width)
        }

        let newSelfSize = resolvedSizes.selfSize
        let newItemSize = resolvedSizes.itemSize
        let itemSizeChanged = itemSize != newItemSize
        let intrinsicHeightChanged = size.height != newSelfSize.height

        lastLaidOutWidth = width
        needsSizingUpdate = false
        itemSize = newItemSize
        size = newSelfSize

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
        if itemSizeChanged {
            collectionView.collectionViewLayout.invalidateLayout()
        }
        collectionView.frame = bounds

        if itemSizeChanged {
            invalidateCollectionLayout()
        }

        if intrinsicHeightChanged {
            invalidateIntrinsicContentSize()
        }
    }

    private func invalidateCollectionLayout() {
        collectionView.collectionViewLayout.invalidateLayout()

        // Force the invalidated attributes to be rebuilt now so an
        // iPad window transition cannot display the previous width for a frame
        // (or indefinitely, if UIKit does not schedule another child layout).
        collectionView.layoutIfNeeded()

        // Scene-geometry transitions can reject a forced child layout while their
        // transaction is still active. Coalesce a second pass onto the next run-loop
        // turn, when UIKit has committed the latest window and collection bounds.
        layoutInvalidationGeneration += 1
        let generation = layoutInvalidationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.layoutInvalidationGeneration == generation else { return }

            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
        }
    }

    private func invalidateSizing() {
        needsSizingUpdate = true
        fittingSizeCache = nil
        lastLaidOutWidth = nil
        itemSize = nil
        itemSizeCache = ItemSizeCache()
        variadicItemSizeCache.removeAll(keepingCapacity: true)

        setNeedsLayout()
        invalidateIntrinsicContentSize()
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

        NSLayoutConstraint.activate([
            snapshot.topAnchor.constraint(equalTo: topAnchor),
            snapshot.bottomAnchor.constraint(equalTo: bottomAnchor),
            snapshot.leadingAnchor.constraint(equalTo: leadingAnchor),
            snapshot.trailingAnchor.constraint(equalTo: trailingAnchor),
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
        collectionView.layoutIfNeeded()
        if collectionView.flowLayout is ColumnAlignedLayout,
           let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        {
            let maximum = max(0, collectionView.contentSize.width - collectionView.bounds.width)
            let offset = (attributes.frame.minX - insets.leading).clamped(to: 0 ... maximum)
            collectionView.setContentOffset(CGPoint(x: offset, y: 0), animated: animated)
        } else {
            let indexPath = IndexPath(row: index, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
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
        let singleItemSize = measuredItemSize(width: metrics.itemWidth(for: availableWidth))

        if let alignedLayout = collectionView.flowLayout as? ColumnAlignedLayout {
            alignedLayout.rows = rows
        }

        let height = metrics.height(for: singleItemSize)
        var flowLayoutItemSize = singleItemSize

        // UICollectionViewFlowLayout requires a one-row item to be strictly shorter
        // than the collection view. One representable floating-point step avoids its
        // invalid-size warning without changing the rendered pixel size.
        if rows == 1, insets.top + insets.bottom <= 0, flowLayoutItemSize.height > 0 {
            flowLayoutItemSize.height = flowLayoutItemSize.height.nextDown
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

    private func measuredItemSize(width: CGFloat? = nil) -> CGSize {
        guard data.isNotEmpty else { return CGSize(width: nonnegativeFinite(width ?? 0), height: 0) }
        return itemSizeCache.size(width: width) {
            contentSize(width: width, element: data[data.startIndex])
        }
    }

    private func contentSize(width: CGFloat?, element: Element) -> CGSize {
        let measurement = ContentMeasurement()
        let root = ContentMeasurementLayout(width: width, measurement: measurement) { viewProvider(element).frame(width: width) }
        let controller = UIHostingController(rootView: root)
        _ = controller.sizeThatFits(in: .zero)
        return CGSize(width: nonnegativeFinite(measurement.size.width), height: nonnegativeFinite(measurement.size.height))
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
        didScrollToItems = configuration.didScrollToItems
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

    private func refreshVisibleItems() {
        for path in collectionView.indexPathsForVisibleItems {
            guard (0 ..< effectiveItemCount).contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? HostingCollectionViewCell<Content> else { continue }
            let item = item(at: path.item)
            cell.setup(view: viewProvider(element(at: path.item)), id: AnyHashable(item.differenceIdentifier))
        }
    }

    // MARK: update

    func update(
        newData: Data,
        alignedLeadingElementID: Binding<ID?>?,
        allowBouncing: Bool? = nil,
        allowScrolling: Bool? = nil,
        dataPrefix: Int? = nil,
        layout newLayout: CollectionHStackLayout,
        insets newInsets: EdgeInsets? = nil,
        itemSpacing newItemSpacing: CGFloat? = nil,
        viewProvider: ((Element) -> Content)? = nil
    ) {

        self.alignedLeadingElementID = alignedLeadingElementID
        let wasEmpty = data.isEmpty
        let insets = newInsets ?? self.insets
        let itemSpacing = newItemSpacing ?? self.itemSpacing
        let sizingConfigurationChanged = newLayout != layout
            || insets != self.insets || itemSpacing != self.itemSpacing

        self.dataPrefix = dataPrefix
        layout = newLayout
        self.insets = insets
        self.itemSpacing = itemSpacing
        if let viewProvider {
            self.viewProvider = viewProvider
        }
        collectionView.flowLayout.sectionInset = .init(top: 0, left: insets.leading, bottom: 0, right: insets.trailing)
        collectionView.flowLayout.minimumLineSpacing = nonnegativeFinite(itemSpacing)
        collectionView.flowLayout.minimumInteritemSpacing = nonnegativeFinite(itemSpacing)

        // data

        var newIndex = dataIndex
        var lookup: [ID: Int]?
        let changedIDs = newIndex.update(from: newData, id: _id, prefix: dataPrefix, lookup: &lookup)
        let newCount = itemCount(for: newIndex)
        let hasDataChanges = changedIDs || newCount != effectiveItemCount

        if hasDataChanges {
            let source = dataIndex.items(count: effectiveItemCount)
            let target = newIndex.items(count: newCount)
            let changes = StagedChangeset(source: source, target: target, section: 0)

            dataUpdateGeneration += 1
            let updateGeneration = dataUpdateGeneration
            isDataUpdateInProgress = true

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self else { return }
                guard self.dataUpdateGeneration == updateGeneration else { return }

                self.isDataUpdateInProgress = false
                self.scheduleAlignedLeadingElementIDUpdate()
            }

            dataTransition = CollectionDataTransition(
                previousData: data, previousIndex: dataIndex, currentIndex: newIndex,
                lookup: &lookup, hasDeletions: changes.contains { !$0.elementDeleted.isEmpty }
            )
            stagedItems = source
            data = newData
            dataIndex = newIndex
            collectionView.reload(using: changes) { items in
                self.stagedItems = items
                self.effectiveItemCount = items.count
            }
            stagedItems = nil
            dataTransition = nil
        } else {
            data = newData
            dataIndex = newIndex
        }
        evaluateInitialElementIfNeeded()
        refreshVisibleItems()

        // allowBouncing

        if let allowBouncing {
            collectionView.bounces = allowBouncing
        }

        // allowScrolling

        if let allowScrolling {
            collectionView.isScrollEnabled = allowScrolling
        }

        if sizingConfigurationChanged || hasDataChanges || wasEmpty != newData.isEmpty {
            invalidateSizing()
        }

        if hasDataChanges {
            CATransaction.commit()
        }

        // DifferenceKit does not call its data setter when there are no changes.
        // Still refresh in case SwiftUI supplied a new Binding instance.
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

        let item = item(at: indexPath.item)
        cell.setup(view: viewProvider(element(at: indexPath.item)), id: AnyHashable(item.differenceIdentifier))

        return cell
    }

    // MARK: UICollectionViewDelegate

    /// Prevents collection items from receiving focus on tvOS.
    public func collectionView(
        _ collectionView: UICollectionView,
        canFocusItemAt indexPath: IndexPath
    ) -> Bool {
        false
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
            size = itemSize ?? computeSizes(forWidth: bounds.width).itemSize
        }

        return CGSize(width: max(size.width, 0), height: max(size.height, 0))
    }

    // MARK: UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {

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

        let reachPosition = collectionView.contentSize.width - collectionView.bounds.width * 2
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

    // TODO: should probably be instead when items just became visible / make separate method?
    // TODO: remove items on edges in certain scrollBehaviors + layouts?
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {

        scheduleAlignedLeadingElementIDUpdate()

        let visibleItems = collectionView
            .indexPathsForVisibleItems
            .map { element(at: $0.item) }

        didScrollToItems(visibleItems)
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

        alignedLeadingElementIDUpdateGeneration += 1
        let updateGeneration = alignedLeadingElementIDUpdateGeneration
        guard alignedLeadingElementID != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.alignedLeadingElementIDUpdateGeneration == updateGeneration else { return }

            self.updateAlignedLeadingElementID()
        }
    }

    private func updateAlignedLeadingElementID() {

        guard let alignedLeadingElementID else { return }
        guard !collectionView.isDragging, !collectionView.isDecelerating else { return }
        guard !isDataUpdateInProgress else { return }

        collectionView.layoutIfNeeded()

        let newID = alignedLeadingElementIDAtCurrentOffset()

        guard alignedLeadingElementID.wrappedValue != newID else { return }
        alignedLeadingElementID.wrappedValue = newID
    }

    private func alignedLeadingElementIDAtCurrentOffset() -> ID? {

        guard collectionView.flowLayout is ColumnAlignedLayout else { return nil }
        guard effectiveItemCount > 0, data.isNotEmpty else { return nil }
        guard collectionView.bounds.width > 0, collectionView.bounds.height > 0 else { return nil }

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
