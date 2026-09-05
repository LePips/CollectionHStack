import DifferenceKit
import SwiftUI

// TODO: comments/documentation
// TODO: fix proxy for index scrolling/paging
// - location: leading/center/trailing
// - account for paging indices
// TODO: did scroll to item with index row?
// TODO: need to determine way for single item sizing item init (first item init?)
// - placeholder views?
// - empty view?
// TODO: fix scroll position on layout change
// TODO: prefetch items rules
// - cancel?
// - must be fresh
// - turn off
// TODO: continuousLeadingBoundary/item paging behavior every X items?
//       - would replace fullpaging
// TODO: have to properly account for CollectionVGridEdgeOffset.columns when rows > 1

// MARK: UICollectionHStack

private let cellReuseIdentifier = "HostingCollectionViewCell"
private let alignedLeadingElementIDUpdateDelay: TimeInterval = 0.05

private enum CollectionSizingSource: String {
    case swiftUIProposal = "SwiftUIProposal"
    case uiKitBounds = "UIKitBounds"
}

public protocol _UICollectionHStack: UIView {

    func scrollTo(index: Int, animated: Bool)
    func snapshotReload()

    /// Returns the index of the given element if its
    /// `id.hashValue` exists in the current `UICollectionHStack`
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

    private var traceLog: CollectionHStackTrace

    private var _id: KeyPath<Element, ID>
    private var currentElementIDHashes: [Int] = []

    // binding
    private var alignedLeadingElementID: Binding<ID?>?
    private var alignedLeadingElementIDUpdateGeneration = 0
    private var dataUpdateGeneration = 0
    private var isDataUpdateInProgress = false

    // events
    private let didScrollToItems: ([Element]) -> Void
    private let onReachedLeadingEdge: () -> Void
    private let onReachedLeadingEdgeOffset: CollectionHStackEdgeOffset
    private let onReachedTrailingEdge: () -> Void
    private let onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset
    private let onPrefetchingElements: ([Element]) -> Void
    private let onCancelPrefetchingElements: ([Element]) -> Void

    // internal
    private var dataPrefix: Int?
    private var effectiveItemCount: Int
    private let isCarousel: Bool
    private var data: Data
    private var insets: EdgeInsets
    private var itemSpacing: CGFloat
    private var measuredItemAspectRatio: CGFloat?
    private var itemSize: CGSize?
    private var layout: CollectionHStackLayout
    private var onReachedEdgeStore: Set<Edge>
    private let scrollBehavior: CollectionHStackScrollBehavior
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
        traceLog: CollectionHStackTrace = .disabled,
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
        self.traceLog = traceLog
        self.viewProvider = viewProvider

        super.init(frame: .zero)

        if isCarousel {
            effectiveItemCount = 100
        }

        proxy.collectionView = self

        collectionView.clipsToBounds = clipsToBounds

        traceLog.info(
            .event,
            "Initialized collection",
            category: .collectionHStack,
            payload: [
                .collectionItemCount(data.count),
                .collectionLayout(layout),
                .collectionScrollBehavior(scrollBehavior),
                .bool("isCarousel", isCarousel),
            ]
        )
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
        layout.minimumLineSpacing = itemSpacing
        layout.minimumInteritemSpacing = itemSpacing

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
        scheduleAlignedLeadingElementIDUpdate()
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            invalidateSizing()
        }
    }

    func fittingSize(forWidth width: CGFloat) -> CGSize {
        guard width.isFinite, width > 0 else {
            return CGSize(width: max(width, 0), height: size.height)
        }

        if let fittingSizeCache, fittingSizeCache.width == width {
            return CGSize(width: width, height: fittingSizeCache.selfSize.height)
        }

        let resolvedSizes = computeSizes(forWidth: width)
        fittingSizeCache = (width, resolvedSizes.selfSize, resolvedSizes.itemSize)

        traceResolvedSizing(
            width: width,
            selfSize: resolvedSizes.selfSize,
            itemSize: resolvedSizes.itemSize,
            source: .swiftUIProposal,
            appliedToLayout: false
        )

        return CGSize(width: width, height: resolvedSizes.selfSize.height)
    }

    private func updateSizes(forWidth width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
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

        if itemSizeChanged || intrinsicHeightChanged {
            traceResolvedSizing(
                width: width,
                selfSize: newSelfSize,
                itemSize: newItemSize,
                source: .uiKitBounds,
                appliedToLayout: true
            )
        }

        if itemSizeChanged {
            invalidateCollectionLayout()
        }

        if intrinsicHeightChanged {
            invalidateIntrinsicContentSize()
        }
    }

    private func traceResolvedSizing(
        width: CGFloat,
        selfSize: CGSize,
        itemSize: CGSize,
        source: CollectionSizingSource,
        appliedToLayout: Bool
    ) {
        traceLog.debug(
            .metric,
            "Resolved collection sizing",
            category: .collectionHStackLayout,
            payload: [
                .string("source", source.rawValue),
                .bool("appliedToLayout", appliedToLayout),
                .collectionDimension("availableWidth", width),
                .collectionDimension("boundsWidth", bounds.width),
                .collectionDimension("collectionHeight", selfSize.height),
                .collectionDimension("itemWidth", itemSize.width),
                .collectionDimension("itemHeight", itemSize.height),
                .collectionDimension("flowLayoutItemWidth", collectionView.flowLayout.itemSize.width),
                .collectionDimension("flowLayoutItemHeight", collectionView.flowLayout.itemSize.height),
                .collectionItemCount(effectiveItemCount),
                .collectionLayout(layout),
            ]
        )
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

            let previousAttributesSize = self.collectionView.collectionViewLayout
                .layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?
                .size

            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()

            guard let previousAttributesSize, let itemSize = self.itemSize,
                  previousAttributesSize != itemSize else { return }

            self.traceLog.debug(
                .state,
                "Reconciled stale collection layout attributes",
                category: .collectionHStackLayout,
                payload: [
                    .collectionDimension("boundsWidth", self.bounds.width),
                    .collectionDimension("previousItemWidth", previousAttributesSize.width),
                    .collectionDimension("previousItemHeight", previousAttributesSize.height),
                    .collectionDimension("itemWidth", itemSize.width),
                    .collectionDimension("itemHeight", itemSize.height),
                ]
            )
        }
    }

    private func invalidateSizing() {
        needsSizingUpdate = true
        fittingSizeCache = nil
        lastLaidOutWidth = nil
        itemSize = nil
        measuredItemAspectRatio = nil
        variadicItemSizeCache.removeAll(keepingCapacity: true)

        setNeedsLayout()
        invalidateIntrinsicContentSize()

        traceLog.debug(
            .state,
            "Invalidated cached sizing",
            category: .collectionHStackLayout,
            payload: [
                .collectionItemCount(effectiveItemCount),
                .collectionLayout(layout),
            ]
        )
    }

    // MARK: proxy

    public func snapshotReload() {
        traceLog.info(
            .action,
            "Started snapshot reload",
            category: .collectionHStackData,
            payload: [.collectionItemCount(effectiveItemCount)]
        )

        invalidateSizing()

        guard let snapshot = collectionView.snapshotView(afterScreenUpdates: false) else {
            collectionView.reloadData()
            scheduleAlignedLeadingElementIDUpdate()

            traceLog.warn(
                .diagnostic,
                "Completed snapshot reload without transition snapshot",
                category: .collectionHStackData,
                payload: [
                    .string("result", "Fallback"),
                    .collectionItemCount(effectiveItemCount),
                ]
            )
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
        } completion: { [weak self] _ in
            snapshot.removeFromSuperview()

            self?.traceLog.info(
                .action,
                "Completed snapshot reload",
                category: .collectionHStackData,
                payload: [
                    .string("result", "Success"),
                    .collectionItemCount(self?.effectiveItemCount ?? 0),
                ]
            )
        }
    }

    // TODO: other layouts implement their own `scrollTo`
    public func scrollTo(index: Int, animated: Bool) {

        traceLog.info(
            .action,
            "Requested scroll to item",
            category: .collectionHStackScrolling,
            payload: [
                .int("targetIndex", index),
                .bool("animated", animated),
                .collectionItemCount(effectiveItemCount),
                .collectionScrollBehavior(scrollBehavior),
            ]
        )

        if let flowLayout = collectionView.flowLayout as? ContinuousLeadingEdgeFlowLayout {
            flowLayout.scrollTo(index: index, animated: animated)
        } else {
            let indexPath = IndexPath(row: index, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
        }

        // Animated scrolling emits did-scroll callbacks which keep postponing this
        // publication until the content offset stops changing.
        scheduleAlignedLeadingElementIDUpdate(after: animated ? alignedLeadingElementIDUpdateDelay : 0)
    }

    public func index(id: some Hashable) -> Int? {
        currentElementIDHashes.firstIndex(of: id.hashValue)
    }

    /// Computes a stable item size from the supplied width rather than reading `bounds`
    /// throughout the calculation. This makes SwiftUI's proposal and UIKit's layout pass
    /// agree on the same height during a resize.
    func computeSizes(forWidth availableWidth: CGFloat) -> (selfSize: CGSize, itemSize: CGSize) {
        let rows: Int
        let singleItemSize: CGSize

        switch layout {
        case let .grid(columns, configuredRows, trailingInset):
            rows = validRows(configuredRows)
            let validColumns = validColumnCount(columns)
            let width = itemWidth(
                availableWidth: availableWidth,
                columns: validColumns,
                trailingInset: trailingInset
            )
            singleItemSize = measuredItemSize(width: width)

        case let .minimumWidth(minimumWidth, configuredRows):
            rows = validRows(configuredRows)
            let validMinimumWidth = validMinimumWidth(minimumWidth)
            let width = itemWidth(
                availableWidth: availableWidth,
                minimumWidth: validMinimumWidth
            )
            singleItemSize = measuredItemSize(width: width)

        case let .selfSizingSameSize(configuredRows),
             let .selfSizingVariadicWidth(configuredRows):
            rows = validRows(configuredRows)
            singleItemSize = measuredItemSize()
        }

        if let alignedLayout = collectionView.flowLayout as? ColumnAlignedLayout {
            alignedLayout.rows = rows
        }

        let spacing = (rows - 1) * itemSpacing
        let height = singleItemSize.height * rows + spacing + insets.bottom + insets.top
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

    private func validRows(_ rows: Int) -> Int {
        guard rows > 0 else {
            traceLog.warn(
                .diagnostic,
                "Invalid row count; using fallback",
                category: .collectionHStackLayout,
                payload: [
                    .int("configuredRows", rows),
                    .int("fallbackRows", 1),
                ]
            )
            return 1
        }
        return rows
    }

    private func validColumnCount(_ columns: CGFloat) -> CGFloat {
        guard columns.isFinite, columns > 0 else {
            traceLog.warn(
                .diagnostic,
                "Invalid column count; using fallback",
                category: .collectionHStackLayout,
                payload: [
                    .collectionDimension("configuredColumns", columns),
                    .collectionDimension("fallbackColumns", 1),
                ]
            )
            return 1
        }
        return columns
    }

    private func validMinimumWidth(_ minimumWidth: CGFloat) -> CGFloat {
        guard minimumWidth.isFinite, minimumWidth > 0 else {
            traceLog.warn(
                .diagnostic,
                "Invalid minimum width; using fallback",
                category: .collectionHStackLayout,
                payload: [
                    .collectionDimension("configuredWidth", minimumWidth),
                    .collectionDimension("fallbackWidth", 1),
                ]
            )
            return 1
        }
        return minimumWidth
    }

    private func measuredItemSize(width: CGFloat? = nil, element: Element? = nil) -> CGSize {
        guard let width else {
            guard !data.isEmpty else { return .zero }
            return contentSize(width: nil, element: element ?? data[0])
        }
        guard width.isFinite, width > 0 else { return .zero }
        guard !data.isEmpty else { return CGSize(width: width, height: 0) }

        if let measuredItemAspectRatio {
            return CGSize(width: width, height: nonnegativeFinite(width / measuredItemAspectRatio))
        }

        let measuredSize = contentSize(width: width, element: element ?? data[0])
        let ratio = measuredSize.width / measuredSize.height
        if ratio.isFinite, ratio > 0 {
            measuredItemAspectRatio = ratio
            return CGSize(width: width, height: nonnegativeFinite(width / ratio))
        }
        return CGSize(width: width, height: measuredSize.height)
    }

    private func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 0) : 0
    }

    private func contentSize(width: CGFloat?, element: Element) -> CGSize {
        let view: AnyView = if let width, width > 0 {
            AnyView(viewProvider(element).frame(width: width))
        } else {
            AnyView(viewProvider(element))
        }

        // Replacing `rootView` on a reused hosting controller does not synchronously
        // invalidate its fitted height. During a live window resize that can return the
        // previous width's height even though the new fixed-width view is installed.
        // A fresh controller makes an explicit remeasurement independent of the old
        // content. Width-constrained layouts cache the measured ratio for resizing.
        let hostingController = UIHostingController(rootView: view)
        hostingController.view.backgroundColor = nil
        hostingController.view.sizeToFit()
        let measuredSize = hostingController.view.bounds.size

        // Keep the measured width and height together. Hosting views can round their
        // bounds, so pairing the requested width with the measured height distorts
        // the ratio and amplifies that error on subsequent resizes.
        return CGSize(
            width: nonnegativeFinite(measuredSize.width),
            height: nonnegativeFinite(measuredSize.height)
        )
    }

    // MARK: update

    func update(
        newData: Data,
        alignedLeadingElementID: Binding<ID?>?,
        allowBouncing: Bool? = nil,
        allowScrolling: Bool? = nil,
        dataPrefix: Int? = nil,
        layout newLayout: CollectionHStackLayout,
        traceLog: CollectionHStackTrace,
        insets newInsets: EdgeInsets? = nil,
        itemSpacing newItemSpacing: CGFloat? = nil,
        viewProvider: ((Element) -> Content)? = nil
    ) {

        self.traceLog = traceLog
        self.alignedLeadingElementID = alignedLeadingElementID
        let wasEmpty = data.isEmpty
        let insets = newInsets ?? self.insets
        let itemSpacing = newItemSpacing ?? self.itemSpacing
        let sizingConfigurationChanged = newLayout != layout
            || insets != self.insets || itemSpacing != self.itemSpacing
        let previousLayout = layout

        self.dataPrefix = dataPrefix
        layout = newLayout
        self.insets = insets
        self.itemSpacing = itemSpacing
        if let viewProvider {
            self.viewProvider = viewProvider
        }
        collectionView.flowLayout.sectionInset = .init(top: 0, left: insets.leading, bottom: 0, right: insets.trailing)
        collectionView.flowLayout.minimumLineSpacing = itemSpacing
        collectionView.flowLayout.minimumInteritemSpacing = itemSpacing

        // data

        let newIDs = newData
            .prefixPositive(self.dataPrefix ?? 0)
            .map { $0[keyPath: _id] }
            .map(\.hashValue)

        let hasDataChanges = currentElementIDHashes != newIDs

        if hasDataChanges {
            let previousItemCount = currentElementIDHashes.count
            let changes = StagedChangeset(
                source: currentElementIDHashes,
                target: newIDs,
                section: 0
            )

            dataUpdateGeneration += 1
            let updateGeneration = dataUpdateGeneration
            isDataUpdateInProgress = true

            traceLog.info(
                .action,
                "Started data update",
                category: .collectionHStackData,
                payload: [
                    .int("previousItemCount", previousItemCount),
                    .collectionItemCount(newIDs.count),
                    .int("generation", updateGeneration),
                ]
            )

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self else { return }
                guard self.dataUpdateGeneration == updateGeneration else { return }

                self.isDataUpdateInProgress = false
                self.scheduleAlignedLeadingElementIDUpdate()

                self.traceLog.info(
                    .action,
                    "Completed data update",
                    category: .collectionHStackData,
                    payload: [
                        .string("result", "Success"),
                        .int("previousItemCount", previousItemCount),
                        .collectionItemCount(self.currentElementIDHashes.count),
                        .int("generation", updateGeneration),
                    ]
                )
            }

            data = newData
            collectionView.reload(using: changes) { data in
                self.effectiveItemCount = data.count
                self.currentElementIDHashes = newIDs
            }
        } else {
            data = newData
        }

        // allowBouncing

        if let allowBouncing {
            if collectionView.bounces != allowBouncing {
                traceLog.info(
                    .state,
                    "Changed bouncing state",
                    category: .collectionHStackScrolling,
                    payload: [.bool("isEnabled", allowBouncing)]
                )
            }
            collectionView.bounces = allowBouncing
        }

        // allowScrolling

        if let allowScrolling {
            if collectionView.isScrollEnabled != allowScrolling {
                traceLog.info(
                    .state,
                    "Changed scrolling state",
                    category: .collectionHStackScrolling,
                    payload: [.bool("isEnabled", allowScrolling)]
                )
            }
            collectionView.isScrollEnabled = allowScrolling
        }

        if sizingConfigurationChanged {
            traceLog.info(
                .state,
                "Changed sizing configuration",
                category: .collectionHStackLayout,
                payload: [
                    .string("previousLayout", previousLayout.logIdentifier),
                    .collectionLayout(newLayout),
                ]
            )
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

        let element = data[indexPath.row % data.count]
        cell.setup(view: viewProvider(element))

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
            guard !data.isEmpty else { return .zero }

            let element = data[indexPath.row % data.count]
            let id = element[keyPath: _id]

            if let cachedSize = variadicItemSizeCache[id] {
                size = cachedSize
            } else {
                let measuredSize = measuredItemSize(element: element)
                variadicItemSizeCache[id] = measuredSize
                size = measuredSize
            }
        } else {
            if itemSize == nil {
                updateSizes(forWidth: bounds.width)
            }
            size = itemSize ?? .zero
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

            reachedLeading = minIndexPath <= columns - 1
        case let .offset(offset):
            reachedLeading = contentOffset <= offset
        }

        if reachedLeading {
            if !onReachedEdgeStore.contains(.leading) {
                onReachedEdgeStore.insert(.leading)

                traceLog.info(
                    .event,
                    "Reached leading edge",
                    category: .collectionHStackScrolling,
                    payload: [
                        .collectionDimension("contentOffset", contentOffset),
                        .collectionItemCount(effectiveItemCount),
                        .int("visibleItemCount", collectionView.indexPathsForVisibleItems.count),
                    ]
                )
                onReachedLeadingEdge()
            }
        } else {
            onReachedEdgeStore.remove(.leading)
        }
    }

    private func handleCarouselReachedTrailingEdge(with contentOffset: CGFloat) {

        let reachPosition = collectionView.contentSize.width - collectionView.bounds.width * 2
        let reachedTrailing = contentOffset >= reachPosition

        if reachedTrailing {
            let previousItemCount = effectiveItemCount
            effectiveItemCount += 100
            collectionView.reloadData()

            traceLog.info(
                .state,
                "Expanded carousel items",
                category: .collectionHStackData,
                payload: [
                    .int("previousItemCount", previousItemCount),
                    .collectionItemCount(effectiveItemCount),
                ]
            )
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

            reachedTrailing = maxIndexPath >= effectiveItemCount - columns
        case let .offset(offset):
            let reachPosition = collectionView.contentSize.width - collectionView.bounds.width - offset
            reachedTrailing = contentOffset >= reachPosition
        }

        if reachedTrailing {
            if !onReachedEdgeStore.contains(.trailing) {
                onReachedEdgeStore.insert(.trailing)

                traceLog.info(
                    .event,
                    "Reached trailing edge",
                    category: .collectionHStackScrolling,
                    payload: [
                        .collectionDimension("contentOffset", contentOffset),
                        .collectionItemCount(effectiveItemCount),
                        .int("visibleItemCount", collectionView.indexPathsForVisibleItems.count),
                    ]
                )
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
            .map { data[$0.row % data.count] }

        traceScrollingSettled(reason: "DecelerationEnded", visibleItemCount: visibleItems.count)

        didScrollToItems(visibleItems)
    }

    public func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        if !decelerate {
            scheduleAlignedLeadingElementIDUpdate()
            traceScrollingSettled(reason: "DraggingEnded")
        }
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scheduleAlignedLeadingElementIDUpdate()
        traceScrollingSettled(reason: "AnimationEnded")
    }

    private func traceScrollingSettled(
        reason: String,
        visibleItemCount: Int? = nil
    ) {
        traceLog.info(
            .state,
            "Scrolling settled",
            category: .collectionHStackScrolling,
            payload: [
                .string("reason", reason),
                .collectionDimension("contentOffset", collectionView.contentOffset.x),
                .int("visibleItemCount", visibleItemCount ?? collectionView.indexPathsForVisibleItems.count),
            ]
        )
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

        let alignedElement = alignedLeadingElementAtCurrentOffset()
        let newID = alignedElement?.id

        guard alignedLeadingElementID.wrappedValue != newID else { return }
        alignedLeadingElementID.wrappedValue = newID

        var payload: [CollectionHStackTrace.Payload] = [
            .bool("hasAlignedElement", newID != nil),
        ]
        if let index = alignedElement?.index {
            payload.append(.int("alignedIndex", index))
        }

        traceLog.info(
            .state,
            "Changed aligned leading element",
            category: .collectionHStackScrolling,
            payload: payload
        )
    }

    private func alignedLeadingElementAtCurrentOffset() -> (id: ID, index: Int)? {

        guard collectionView.flowLayout is ColumnAlignedLayout else { return nil }
        guard effectiveItemCount > 0, !data.isEmpty else { return nil }
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

        let element = data[alignedIndexPath.item % data.count]
        return (element[keyPath: _id], alignedIndexPath.item)
    }

    // MARK: item width

    private func itemWidth(
        availableWidth: CGFloat,
        columns: CGFloat,
        trailingInset: CGFloat = 0
    ) -> CGFloat {
        let itemSpaces: CGFloat
        let sectionInsets: CGFloat

        if floor(columns) == columns {
            itemSpaces = max(columns - 1, 0)
            sectionInsets = collectionView.flowLayout.sectionInset.horizontal
        } else {
            itemSpaces = max(floor(columns), 0)
            sectionInsets = collectionView.flowLayout.sectionInset.left
        }

        let itemSpacing = itemSpaces * collectionView.flowLayout.minimumInteritemSpacing
        let totalNegative = sectionInsets + itemSpacing + trailingInset

        return max((availableWidth - totalNegative) / columns, 0)
    }

    private func itemWidth(availableWidth: CGFloat, minimumWidth: CGFloat) -> CGFloat {
        let layout = collectionView.flowLayout
        let contentWidth = max(availableWidth - layout.sectionInset.horizontal, 0)
        let widthAndSpacing = minimumWidth + layout.minimumInteritemSpacing
        let columns: CGFloat = if widthAndSpacing > 0 {
            max(floor((contentWidth + layout.minimumInteritemSpacing) / widthAndSpacing), 1)
        } else {
            1
        }

        return itemWidth(availableWidth: availableWidth, columns: columns)
    }

    // MARK: UICollectionViewDataSourcePrefetching

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let prefetchingElements = indexPaths.map { data[$0.row % data.count] }

        traceLog.debug(
            .event,
            "Requested item prefetch",
            category: .collectionHStackPrefetch,
            payload: [.count(prefetchingElements.count)]
        )

        onPrefetchingElements(prefetchingElements)
    }

    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let cancellingElements = indexPaths.map { data[$0.row % data.count] }

        traceLog.debug(
            .event,
            "Cancelled item prefetch",
            category: .collectionHStackPrefetch,
            payload: [.count(cancellingElements.count)]
        )

        onCancelPrefetchingElements(cancellingElements)
    }
}
