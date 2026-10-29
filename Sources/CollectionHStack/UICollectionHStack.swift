#if canImport(UIKit)
import DifferenceKit
import SwiftUI

// UIKit supplies reuse, focus, and animated updates. Measurement is cached separately
// so SwiftUI proposals do not overwrite the collection's live layout during resizing.

// MARK: UICollectionHStack

private let cellReuseIdentifier = "HostingCollectionViewCell"
private let alignedLeadingElementIDUpdateDelay: TimeInterval = 0.05
/// Visible content refreshes wait this long after the latest width change.
private let resizeSettleDelay: TimeInterval = 0.1

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
    private var itemSizeCache = ItemSizeCache()
    private var itemSize: CGSize?
    private var layout: CollectionHStackLayout
    private var onReachedEdgeStore: Set<Edge>
    private var scrollBehavior: CollectionHStackScrollBehavior
    private var initialElementID: ID?
    private var hasEvaluatedInitialElement = false
    private var pendingInitialElementID: ID?
    private var fittingSizeCache: (width: CGFloat, selfSize: CGSize, itemSize: CGSize)?
    private var itemSizeTransition: ItemSizeTransition?
    private var needsResizeTarget = true
    private var pendingSizeTransition: ItemSizeTransition?
    private var lastLaidOutWidth: CGFloat?
    private var needsSizingUpdate = true
    private var renderingInsets: UIEdgeInsets = .zero
    private var size = CGSize(width: UIView.noIntrinsicMetric, height: 0)
    private var variadicItemSizeCache: [ID: CGSize] = [:]
    private var measurer = ContentMeasurer<Content>()

    // resizing
    private var contentGeneration = 0
    private var needsContentRefresh = false
    private var contentRefreshGeneration = 0
    private var lastResizeTime: CFTimeInterval = -.infinity
    /// Unlike `lastLaidOutWidth`, this survives sizing invalidation so a remeasured
    /// layout still preserves the scroll position of the one it replaces.
    private var lastAppliedWidth: CGFloat?
    private var scrollAnchor: ScrollAnchor?
    private var isAdjustingScrollPosition = false
    private var isLayoutDeferred = false
    private var isForcingLayout = false
    private var visibilityObservations: [NSKeyValueObservation] = []

    /// The position to preserve when item geometry changes, matching the scroll
    /// behavior's own alignment. Recorded once, then reused across consecutive
    /// resizes so pixel-rounded offsets cannot accumulate drift.
    private enum ScrollAnchor {
        case leading
        case trailing
        case page(CGFloat)
        case item(index: Int, fraction: CGFloat, centered: Bool)
    }

    // MARK: view provider

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
        self._id = id
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

        dataIndex.update(from: data, id: _id, prefix: dataPrefix)
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
            top: 0,
            left: insets.leading,
            bottom: 0,
            right: insets.trailing
        )
        layout.minimumLineSpacing = nonnegativeFinite(itemSpacing)
        layout.minimumInteritemSpacing = nonnegativeFinite(itemSpacing)

        #if os(tvOS)
        let collectionView = FocusCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.identityAt = { [weak self] path in
            guard let self, path.section == 0, (0 ..< self.effectiveItemCount).contains(path.item) else { return nil }

            return AnyHashable(self.item(at: path.item).differenceIdentifier)
        }
        collectionView.indexPathForIdentity = { [weak self] identity in
            guard let self, let identity = identity.base as? CollectionItem<ID>.Identity else { return nil }

            if let stagedItems = self.stagedItems {
                return stagedItems.firstIndex { $0.differenceIdentifier == identity }.map { IndexPath(item: $0, section: 0) }
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
        if needsContentRefresh {
            refreshVisibleItems()
        }
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
        needsResizeTarget = true
        pendingSizeTransition = nil
    }

    /// SwiftUI measures the destination before proposing the intermediate widths
    /// of an animated layout. Capture it for each update, including interrupted
    /// animations, rather than asking callers to duplicate their layout sizing.
    func fittingSize(forProposedWidth width: CGFloat) -> CGSize {
        guard width.isFiniteAndPositive else { return fittingSize(forWidth: width) }

        let tolerance = 0.5 / max(traitCollection.displayScale, 1)
        let isCurrentWidth = abs(width - bounds.width) <= tolerance
        let completedResize = itemSizeTransition.map {
            abs(bounds.width - $0.targetWidth) <= tolerance && abs(width - $0.targetWidth) > tolerance
        } ?? false
        if needsResizeTarget, isCurrentWidth, itemSizeTransition?.progress(for: bounds.width) != nil {
            // An update that leaves the row in place, such as an environment
            // change during an animation, continues the transition it displays.
            needsResizeTarget = false
            pendingSizeTransition = nil
        } else if needsResizeTarget || (!isCurrentWidth && (itemSizeTransition == nil || completedResize)) {
            needsResizeTarget = false
            itemSizeTransition = sizeTransition(to: width)
            pendingSizeTransition = nil
            fittingSizeCache = nil
        } else if width == itemSizeTransition?.targetWidth {
            pendingSizeTransition = nil
        } else if let pendingSizeTransition,
                  abs(width - pendingSizeTransition.sourceWidth) + pixelAlignmentDistance
                  < abs(pendingSizeTransition.targetWidth - pendingSizeTransition.sourceWidth)
        {
            // Retained subtrees can animate without updateUIView. SwiftUI probes
            // the destination before the first animation frame; confirm it when
            // a subsequent proposal is closer to the still-displayed source.
            // SwiftUI also proposes each frame again after aligning it to pixels,
            // which can move it back toward the source; that is the same frame.
            itemSizeTransition = pendingSizeTransition
            self.pendingSizeTransition = nil
            fittingSizeCache = nil
        } else if !isCurrentWidth, pendingSizeTransition == nil {
            pendingSizeTransition = sizeTransition(to: width)
        }
        return fittingSize(forWidth: width)
    }

    /// Aligning both edges of a frame to pixels can change its width by up to one pixel.
    private var pixelAlignmentDistance: CGFloat {
        1 / max(traitCollection.displayScale, 1)
    }

    private func sizeTransition(to width: CGFloat) -> ItemSizeTransition? {
        // A transition narrower than the alignment tolerance has no meaningful
        // progress; any later width would extrapolate its endpoints.
        let tolerance = 0.5 / max(traitCollection.displayScale, 1)
        guard bounds.width.isFiniteAndPositive, abs(bounds.width - width) > tolerance, size.height > 0,
              let targetItemWidth = layoutMetrics.itemWidth(for: width) else { return nil }

        return ItemSizeTransition(
            sourceWidth: bounds.width, targetWidth: width,
            sourceItemSize: itemSize ?? collectionView.flowLayout.itemSize,
            targetItemWidth: targetItemWidth
        )
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
        // A proposal that becomes the live bounds was an animation frame, not
        // an additional destination to use when the parent measures again.
        if let pendingSizeTransition {
            let direction: CGFloat = pendingSizeTransition.targetWidth > pendingSizeTransition.sourceWidth ? 1 : -1
            if (width - pendingSizeTransition.targetWidth) * direction >= -pixelAlignmentDistance {
                self.pendingSizeTransition = nil
            }
        }
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
                lastResizeTime = CACurrentMediaTime()
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
        let requiresImmediateLayout = itemSizeTransition == nil || window == nil
            || width == itemSizeTransition?.targetWidth || pendingInitialElementID != nil
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
    private func currentScrollAnchor() -> ScrollAnchor? {
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
    private func restoreScrollPosition(to anchor: ScrollAnchor) {
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
        .init(top: 0, left: insets.leading + renderingInsets.left, bottom: 0, right: insets.trailing + renderingInsets.right)
    }

    private var renderingFrame: CGRect {
        bounds.inset(by: .init(top: 0, left: -renderingInsets.left, bottom: 0, right: -renderingInsets.right))
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

    private func invalidateSizing() {
        needsSizingUpdate = true
        fittingSizeCache = nil
        itemSizeTransition = nil
        pendingSizeTransition = nil
        lastLaidOutWidth = nil
        itemSize = nil
        itemSizeCache = ItemSizeCache()
        variadicItemSizeCache.removeAll(keepingCapacity: true)
        measurer = ContentMeasurer()

        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    // MARK: content refresh

    /// Supplies the latest views to visible cells that predate the current content generation.
    private func refreshVisibleItems() {
        needsContentRefresh = false
        for path in collectionView.indexPathsForVisibleItems {
            guard (0 ..< effectiveItemCount).contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? HostingCollectionViewCell<Content>,
                  cell.contentGeneration != contentGeneration else { continue }

            configure(cell, at: path.item)
        }
    }

    /// Containers that adapt to their width update every row on each resize frame,
    /// usually without changing any item content. Visible cells are already laid out
    /// again at their new size, so refreshing their content as well would rebuild
    /// every hosted view each frame. Defer it until the width settles; cells that
    /// appear meanwhile are configured with the latest content as usual.
    private func refreshContentIfSettled() {
        guard needsContentRefresh else { return }

        let remaining = lastResizeTime + resizeSettleDelay - CACurrentMediaTime()
        guard remaining > 0, window != nil else {
            refreshVisibleItems()
            return
        }

        contentRefreshGeneration &+= 1
        let generation = contentRefreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.contentRefreshGeneration == generation else { return }

            self.refreshContentIfSettled()
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
        let singleItemSize: CGSize
        if let transition = itemSizeTransition, let progress = transition.progress(for: availableWidth) {
            // Measure the destination once. Interpolating the two measured sizes
            // preserves fixed-height text and padding without rebuilding a sizing
            // host for every frame, including rows outside the visible viewport.
            let targetSize = measuredItemSize(width: transition.targetItemWidth)
            singleItemSize = transition.itemSize(at: progress, targetSize: targetSize)
        } else {
            singleItemSize = measuredItemSize(width: metrics.itemWidth(for: availableWidth))
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

        // UICollectionViewFlowLayout requires a one-row item to be strictly shorter
        // than the collection view. One representable floating-point step avoids its
        // invalid-size warning without changing the rendered pixel size.
        if rows == 1, insets.top + insets.bottom <= 0, flowLayoutItemSize.height > 0 {
            flowLayoutItemSize.height = min(flowLayoutItemSize.height, height).nextDown
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
        measurer.size(of: viewProvider(element), identity: AnyHashable(element[keyPath: _id]), width: width)
    }

    private func configure(_ cell: HostingCollectionViewCell<Content>, at position: Int) {
        cell.setup(
            view: viewProvider(element(at: position)),
            id: AnyHashable(item(at: position).differenceIdentifier),
            generation: contentGeneration
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

        layout = newLayout
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
                guard let self, self.dataUpdateGeneration == updateGeneration else { return }

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
            scrollAnchor = nil
        } else {
            data = newData
            dataIndex = newIndex
        }
        evaluateInitialElementIfNeeded()

        // Every visible cell, including those configured during staged updates,
        // now predates the latest data and view provider. SwiftUI lays out the
        // representable before rendering, which lets resizes skip the refresh.
        contentGeneration &+= 1
        if !defersContentRefresh || hasDataChanges || sizingConfigurationChanged || window == nil {
            refreshVisibleItems()
        } else {
            needsContentRefresh = true
            setNeedsLayout()
        }

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

        // UIKit can request metrics between the parent's resize and the child's
        // bounds update. Keep those temporary attributes inside the actual viewport
        // without replacing the measured size used when the transition finishes.
        let contentInsets = collectionView.adjustedContentInset
        let sectionInsets = collectionView.flowLayout.sectionInset
        let availableHeight = collectionView.bounds.height
            - contentInsets.top - contentInsets.bottom
            - sectionInsets.top - sectionInsets.bottom
        let height = availableHeight > 0 ? min(size.height, availableHeight.nextDown) : size.height

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

        alignedLeadingElementIDUpdateGeneration += 1
        let updateGeneration = alignedLeadingElementIDUpdateGeneration
        guard alignedLeadingElementID != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.alignedLeadingElementIDUpdateGeneration == updateGeneration else { return }

            self.updateAlignedLeadingElementID()
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
