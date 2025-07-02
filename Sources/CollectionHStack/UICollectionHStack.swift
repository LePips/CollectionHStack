import DifferenceKit
import OSLog
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
// TODO: guard against negative sizes (why happening?)
//       - not just when elements are zeroed
// TODO: relayout when items no longer empty
// TODO: have to properly account for CollectionVGridEdgeOffset.columns when rows > 1

// MARK: UICollectionHStack

private let cellReuseIdentifier = "HostingCollectionViewCell"

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

    private let logger = Logger()

    private var _id: KeyPath<Element, ID>
    private var currentElementIDHashes: [Int] = []

    // events
    private let didScrollToItems: ([Element]) -> Void
    private let onReachedLeadingEdge: () -> Void
    private let onReachedLeadingEdgeOffset: CollectionHStackEdgeOffset
    private let onReachedTrailingEdge: () -> Void
    private let onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset

    // internal
    private var dataPrefix: Int?
    private var effectiveItemCount: Int
    private let isCarousel: Bool
    private var data: Data
    private let insets: EdgeInsets
    private let itemSpacing: CGFloat
    private var itemSize: CGSize!
    private var layout: CollectionHStackLayout
    private var onReachedEdgeStore: Set<Edge>
    private var prefetchedViewCache: [Int: UIHostingController<Content>]
    private let scrollBehavior: CollectionHStackScrollBehavior

    private var size: CGSize {
        didSet {
            let isAnimating = CATransaction.animationDuration() > 0

            if isAnimating {
                CATransaction.begin()
                let context = UICollectionViewFlowLayoutInvalidationContext()
                context.invalidateFlowLayoutDelegateMetrics = true
                context.invalidateFlowLayoutAttributes = true
                collectionView.flowLayout.invalidateLayout(with: context)
                CATransaction.commit()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.collectionView.collectionViewLayout.invalidateLayout()
                }
            }

            invalidateIntrinsicContentSize()
        }
    }

    // view providers
    private let viewProvider: (Element) -> Content

    // MARK: init

    init(
        id: KeyPath<Element, ID>,
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
        proxy: CollectionHStackProxy,
        scrollBehavior: CollectionHStackScrollBehavior,
        viewProvider: @escaping (Element) -> Content
    ) {
        self._id = id
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
        self.onReachedEdgeStore = []
        self.prefetchedViewCache = [:]
        self.scrollBehavior = scrollBehavior
        self.size = .zero
        self.viewProvider = viewProvider

        super.init(frame: .zero)

        if isCarousel {
            effectiveItemCount = 100
        }

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
        super.layoutSubviews()

        resize()
    }

    private func resize() {
        let (newSelfSize, newItemSize) = computeSizes()

        if maxAbsDifference(newSelfSize, size) > 1.0 {
            size = newSelfSize
            itemSize = newItemSize
        }
    }

    // MARK: proxy

    // TODO: should recompute height?
    public func snapshotReload() {

        guard let snapshot = collectionView.snapshotView(afterScreenUpdates: false) else {
            collectionView.reloadData()
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

        UIView.animate(withDuration: 0.1) {
            snapshot.alpha = 0
            self.collectionView.alpha = 1
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }

    // TODO: other layouts implement their own `scrollTo`
    public func scrollTo(index: Int, animated: Bool) {
        if let flowLayout = collectionView.flowLayout as? ContinuousLeadingEdgeFlowLayout {
            flowLayout.scrollTo(index: index, animated: animated)
        } else {
            let indexPath = IndexPath(row: index, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
        }
    }

    public func index(id: some Hashable) -> Int? {
        currentElementIDHashes.firstIndex(of: id.hashValue)
    }

    /// In the event of an invalid layout, warnings are logged and a corrected layout will be applied instead
    func computeSizes() -> (selfSize: CGSize, itemSize: CGSize) {

        let _rows: Int
        let singleItemSize: CGSize

        switch layout {
        case let .grid(columns, rows, trailingInset):

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .grid(columns: columns, rows: 1, columnTrailingInset: trailingInset)
                return computeSizes()
            }

            _rows = rows

            guard columns > 0 else {
                logger.warning("Given `columns` is less than or equal to 0, setting to single column display instead.")
                layout = .grid(columns: 1, rows: rows, columnTrailingInset: trailingInset)
                return computeSizes()
            }

            let itemWidth = itemSize(for: layout).width

            singleItemSize = self.singleItemSize(width: itemWidth)

        case let .minimumWidth(minWidth, rows):

            guard minWidth > 0 else {
                logger.warning("Given `minWidth` is less than or equal to 0, setting to single column display instead.")
                layout = .grid(columns: 1, rows: rows, columnTrailingInset: 0)
                return computeSizes()
            }

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .minimumWidth(columnWidth: minWidth, rows: 1)
                return computeSizes()
            }

            _rows = rows

            let itemWidth = itemSize(for: layout).width

            singleItemSize = self.singleItemSize(width: itemWidth)

        case let .selfSizingSameSize(rows):

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .selfSizingSameSize(rows: 1)
                return computeSizes()
            }

            _rows = rows

            singleItemSize = self.singleItemSize()

        case let .selfSizingVariadicWidth(rows):

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .selfSizingVariadicWidth(rows: 1)
                return computeSizes()
            }

            _rows = rows

            singleItemSize = self.singleItemSize()
        }

        if let alignedLayout = (collectionView.flowLayout as? ColumnAlignedLayout) {
            alignedLayout.rows = _rows
        }

        let spacing = (_rows - 1) * itemSpacing
        let height = singleItemSize.height * _rows + spacing + insets.bottom + insets.top

        let selfSize = CGSize(
            width: UIView.noIntrinsicMetric,
            height: height
        )

        return (selfSize, singleItemSize)
    }

    private func singleItemSize(width: CGFloat? = nil) -> CGSize {

        guard !data.isEmpty else { return .init(width: width ?? 0, height: 0) }

        let targetSize: CGSize
        let view: AnyView

        if let width, width > 0 {
            targetSize = CGSize(
                width: width,
                height: UIView.layoutFittingExpandedSize.height
            )
            view = AnyView(viewProvider(data[0]).frame(width: width))
        } else {
            targetSize = UIView.layoutFittingExpandedSize
            view = AnyView(viewProvider(data[0]))
        }

        let hostingController = UIHostingController(rootView: view)
        hostingController.view.sizeToFit()
        return hostingController.view.bounds.size
    }

    // MARK: update

    func update(
        newData: Data,
        allowBouncing: Bool? = nil,
        allowScrolling: Bool? = nil,
        dataPrefix: Int? = nil,
        layout newLayout: CollectionHStackLayout
    ) {

        if let dataPrefix {
            self.dataPrefix = dataPrefix
        }

        // data

        let newIDs = newData
            .prefixPositive(self.dataPrefix ?? 0)
            .map { $0[keyPath: _id] }
            .map(\.hashValue)

        let changes = StagedChangeset(
            source: currentElementIDHashes,
            target: newIDs,
            section: 0
        )

        data = newData

        collectionView.reload(using: changes) { data in
            self.effectiveItemCount = data.count
            self.currentElementIDHashes = newIDs
        }

        // allowBouncing

        if let allowBouncing {
            collectionView.bounces = allowBouncing
        }

        // allowScrolling

        if let allowScrolling {
            collectionView.isScrollEnabled = allowScrolling
        }

        if newLayout != layout {
            layout = newLayout
            resize()
        }
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

        let item = data[indexPath.row % data.count]

        if let prefetched = prefetchedViewCache[indexPath.row] {
            cell.setup(hostingController: prefetched)
        } else {
            cell.setup(view: viewProvider(item))
        }

        return cell
    }

    // MARK: UICollectionViewDelegate

    // required for tvOS
    public func collectionView(
        _ collectionView: UICollectionView,
        canFocusItemAt indexPath: IndexPath
    ) -> Bool {
        false
    }

    // MARK: UICollectionViewDelegateFlowLayout

    // TODO: should we protect against size changes?
    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {

        let size: CGSize

        if case CollectionHStackLayout.selfSizingVariadicWidth = layout {

            let item = data[indexPath.row]

            if let prefetched = prefetchedViewCache[indexPath.row] {
                prefetched.view.sizeToFit()
                size = prefetched.view.bounds.size
            } else {
                let singleItem = UIHostingController(rootView: viewProvider(item))
                singleItem.view.sizeToFit()
                size = singleItem.view.bounds.size
            }
        } else {
            if let itemSize {
                size = itemSize
            } else {
                itemSize = itemSize(for: layout)
                size = itemSize
            }

            // TODO: document this + `scrollTo` behavior
            collectionView.flowLayout.itemSize = size
        }

        return max(size, .zero)
    }

    // MARK: UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {

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

            reachedLeading = minIndexPath ?? 0 <= columns - 1
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

        if reachedTrailing {
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

            reachedTrailing = maxIndexPath >= effectiveItemCount - columns
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

        let visibleItems = collectionView
            .indexPathsForVisibleItems
            .map { data[$0.row % data.count] }

        didScrollToItems(visibleItems)
    }

    // MARK: item size

    /// - Precondition: rows > 0
    private func itemSize(for layout: CollectionHStackLayout) -> CGSize {

        let _rows: Int
        let width: CGFloat

        switch layout {
        case let .grid(columns, rows, trailingInset):
            _rows = rows
            width = itemWidth(columns: columns, trailingInset: trailingInset)

        case let .minimumWidth(minWidth, rows):
            _rows = rows
            width = itemWidth(minWidth: minWidth)

        case .selfSizingSameSize, .selfSizingVariadicWidth:
            return singleItemSize()
        }

        let insets = insets.bottom + insets.top
        let spacing = (_rows - 1) * itemSpacing

        precondition(_rows > 0)

        // Note: `floor` because iOS 15 doesn't like cell height ==
        //       collection view height. At worse, this creates a
        //       few pixel padding.

        return CGSize(
            width: width,
            height: floor((size.height - spacing - insets) / _rows)
        )
    }

    // MARK: item width

    /// - Precondition: columns > 0
    private func itemWidth(columns: CGFloat, trailingInset: CGFloat = 0) -> CGFloat {

        precondition(columns > 0, "Given `columns` is less than or equal to 0")

        let itemSpaces: CGFloat
        let sectionInsets: CGFloat

        if floor(columns) == columns {
            itemSpaces = columns - 1
            sectionInsets = collectionView.flowLayout.sectionInset.horizontal
        } else {
            itemSpaces = floor(columns)
            sectionInsets = collectionView.flowLayout.sectionInset.left
        }

        let itemSpacing = itemSpaces * collectionView.flowLayout.minimumInteritemSpacing
        let totalNegative = sectionInsets + itemSpacing + trailingInset

        return (bounds.width - totalNegative) / columns
    }

    /// - Precondition: minWidth > 0
    private func itemWidth(minWidth: CGFloat) -> CGFloat {

        precondition(minWidth > 0, "Given `minWidth` is less than or equal to 0")

        // Ensure that each item has a given minimum width
        let layout = collectionView.flowLayout
        var columns = CGFloat(Int((bounds.width - layout.sectionInset.horizontal) / minWidth))

        guard columns != 1 else { return itemWidth(columns: 1) }

        let preItemSpacing = (columns - 1) * layout.minimumInteritemSpacing

        let totalNegative = layout.sectionInset.horizontal + preItemSpacing

        // if adding negative space with current column count would result in column sizes < minWidth
        if columns * minWidth + totalNegative > bounds.width {
            columns -= 1
        }

        return itemWidth(columns: columns)
    }

    // MARK: UICollectionViewDataSourcePrefetching

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let fetchedItems = indexPaths.map { data[$0.row % data.count] }

        for path in indexPaths {
            let item = data[path.row % data.count]
            let premade = UIHostingController(rootView: viewProvider(item))
            prefetchedViewCache[path.row] = premade
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for path in indexPaths {
            prefetchedViewCache.removeValue(forKey: path.row)
        }
    }
}
