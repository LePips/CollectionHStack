import DifferenceKit
import OrderedCollections
import OSLog
import SwiftUI

// TODO: comments/documentation
// TODO: proxy for index selection/paging
// - look at bindings instead of a proxy object?
// TODO: did scroll to item with index row?
// TODO: need to determine way for single item sizing item init (first item init?)
// - placeholder views?
// - empty view?
// TODO: fix scroll position on layout change
// TODO: allow passing height info and widths are calculated instead?
// TODO: prefetch items rules
// - cancel?
// - must be fresh
// - turn off
// TODO: continuousLeadingBoundary/item paging behavior every X items?
// TODO: different default insets/spacing for tvOS
// TODO: tvOS spacing issue with Button focus
// - can be solved with padding but should do that here (see vertical insets)?
// TODO: deceleration customization

// MARK: UICongruentScrollView

class UICongruentScrollView<Item: Hashable>: UIView,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout,
    UICollectionViewDataSourcePrefetching
{

    private let logger = Logger()

    // carousel
    private var isCarousel: Bool
    private var effectiveItemCount = 100

    // events
    private let didScrollToItems: ([Item]) -> Void
    private let onReachedLeadingEdge: () -> Void
    private let onReachedLeadingEdgeOffset: CGFloat
    private let onReachedTrailingEdge: () -> Void
    private let onReachedTrailingEdgeOffset: CGFloat

    // internal
    private let bottomInset: CGFloat
    private var effectiveWidth: CGFloat
    private let horizontalInset: CGFloat
    private var items: Binding<OrderedSet<Item>>
    private let itemSpacing: CGFloat
    private var itemSize: CGSize!
    private var layout: CongruentScrollingHStackLayout
    private var onReachedEdgeStore: Set<Edge>
    private var prefetchedViewCache: [Int: UIHostingController<AnyView>]
    private let scrollBehavior: CongruentScrollingHStackScrollBehavior
    private var size: CGSize {
        didSet {
            itemSize = itemSize(for: layout)
            invalidateIntrinsicContentSize()
            collectionView.collectionViewLayout.prepare()
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    private let topInset: CGFloat

    // view providers
    private let viewProvider: (Item) -> any View

    // MARK: init

    init(
        bottomInset: CGFloat,
        clipsToBounds: Bool,
        didScrollToItems: @escaping ([Item]) -> Void,
        horizontalInset: CGFloat,
        isCarousel: Bool,
        items: Binding<OrderedSet<Item>>,
        itemSpacing: CGFloat,
        layout: CongruentScrollingHStackLayout,
        onReachedLeadingEdge: @escaping () -> Void,
        onReachedLeadingEdgeOffset: CGFloat,
        onReachedTrailingEdge: @escaping () -> Void,
        onReachedTrailingEdgeOffset: CGFloat,
        scrollBehavior: CongruentScrollingHStackScrollBehavior,
        sizeObserver: SizeObserver,
        topInset: CGFloat,
        viewProvider: @escaping (Item) -> any View
    ) {
        self.bottomInset = bottomInset
        self.didScrollToItems = didScrollToItems
        self.effectiveWidth = 0
        self.horizontalInset = horizontalInset
        self.isCarousel = isCarousel
        self.items = items
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
        self.topInset = topInset
        self.viewProvider = viewProvider

        super.init(frame: .zero)

        sizeObserver.onSizeChanged = { newSize in
            self.effectiveWidth = newSize.width
            self.layoutSubviews()
        }

        collectionView.clipsToBounds = clipsToBounds

        updateItems(with: items, allowScrolling: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        size
    }

    // MARK: collectionView

    private lazy var collectionView: UICollectionView = {

        let layout = scrollBehavior.flowLayout
        layout.scrollDirection = .horizontal
        layout.sectionInset = .init(
            top: 0,
            left: horizontalInset,
            bottom: 0,
            right: horizontalInset
        )
        layout.minimumLineSpacing = itemSpacing
        layout.minimumInteritemSpacing = itemSpacing

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(HostingCollectionViewCell.self, forCellWithReuseIdentifier: HostingCollectionViewCell.reuseIdentifier)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = nil
        collectionView.bounces = true

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

    override func layoutSubviews() {
        super.layoutSubviews()

        size = computeSize()
        updateItems(with: items)
    }

    /// Computes the size that this view should be based on the effectiveWidth and the total item content height
    ///
    /// In the event of an invalid layout, warnings are logged and a corrected layout will be applied instead
    private func computeSize() -> CGSize {

        let _rows: Int
        let singleItemHeight: CGFloat

        switch layout {
        case let .grid(columns, rows, trailingInset):

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .grid(columns: columns, rows: 1, columnTrailingInset: trailingInset)
                return computeSize()
            }

            _rows = rows

            guard columns > 0 else {
                logger.warning("Given `columns` is less than or equal to 0, setting to single column display instead.")
                layout = .grid(columns: 1, rows: rows, columnTrailingInset: trailingInset)
                return computeSize()
            }

            let itemWidth = itemSize(for: layout).width

            singleItemHeight = singleItemSize(width: itemWidth).height

        case let .minimumWidth(minWidth, rows):

            guard minWidth > 0 else {
                logger.warning("Given `minWidth` is less than or equal to 0, setting to single column display instead.")
                layout = .grid(columns: 1, rows: rows, columnTrailingInset: 0)
                return computeSize()
            }

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .minimumWidth(columnWidth: minWidth, rows: 1)
                return computeSize()
            }

            _rows = rows

            let itemWidth = itemSize(for: layout).width

            singleItemHeight = singleItemSize(width: itemWidth).height

        case let .selfSizingSameSize(rows):

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .selfSizingSameSize(rows: 1)
                return computeSize()
            }

            _rows = rows

            singleItemHeight = singleItemSize().height

        case let .selfSizingVariadicWidth(rows):

            guard rows > 0 else {
                logger.warning("Given `rows` is less than or equal to 0, setting to single row display instead.")
                layout = .selfSizingVariadicWidth(rows: 1)
                return computeSize()
            }

            _rows = rows

            singleItemHeight = singleItemSize().height
        }

        if let alignedLayout = (collectionView.flowLayout as? ColumnAlignedLayout) {
            alignedLayout.rows = _rows
        }

        let spacing = (_rows - 1) * itemSpacing
        let height = singleItemHeight * _rows + spacing + bottomInset + topInset

        return CGSize(width: effectiveWidth, height: height)
    }

    private func singleItemSize(width: CGFloat? = nil) -> CGSize {

        guard !items.wrappedValue.isEmpty else { return .init(width: width ?? 0, height: 0) }

        let view: AnyView

        if let width, width > 0 {
            view = AnyView(viewProvider(items.wrappedValue[0]).frame(width: width))
        } else {
            view = AnyView(viewProvider(items.wrappedValue[0]))
        }

        let singleItem = UIHostingController(rootView: view)
        singleItem.view.sizeToFit()
        return singleItem.view.bounds.size
    }

    // MARK: updateItems

    func updateItems(
        with newItems: Binding<OrderedSet<Item>>,
        allowBouncing: Bool? = nil,
        allowScrolling: Bool? = nil
    ) {

        let changes = StagedChangeset(
            source: items.wrappedValue.map(\.hashValue),
            target: newItems.wrappedValue.map(\.hashValue),
            section: 0
        )

        items = newItems

        collectionView.reload(using: changes) { _ in
            // we already set the new binding
        }

        if let allowBouncing {
            collectionView.bounces = allowBouncing
        }

        if let allowScrolling {
            collectionView.isScrollEnabled = allowScrolling
        }
    }

    // MARK: UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {

        // leading edge
        let reachedLeadingPosition = onReachedLeadingEdgeOffset
        let reachedLeading = scrollView.contentOffset.x <= reachedLeadingPosition

        if reachedLeading {
            if !onReachedEdgeStore.contains(.leading) {
                onReachedEdgeStore.insert(.leading)
                onReachedLeadingEdge()
            }
        } else {
            onReachedEdgeStore.remove(.leading)
        }

        // trailing edge
        if isCarousel {
            let reachPosition = scrollView.contentSize.width - scrollView.bounds.width * 2
            let reachedTrailing = scrollView.contentOffset.x >= reachPosition

            if reachedTrailing {
                effectiveItemCount += 100
                collectionView.reloadData()
            }
        } else {
            let reachPosition = scrollView.contentSize.width - scrollView.bounds.width - onReachedTrailingEdgeOffset
            let reachedTrailing = scrollView.contentOffset.x >= reachPosition

            if reachedTrailing {
                if !onReachedEdgeStore.contains(.trailing) {
                    onReachedEdgeStore.insert(.trailing)
                    onReachedTrailingEdge()
                }
            } else {
                onReachedEdgeStore.remove(.trailing)
            }
        }
    }

    // TODO: should probably be instead when items just became visible / make separate method?
    // TODO: remove items on edges in certain scrollBehaviors + layouts?
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {

        let visibleItems = collectionView
            .indexPathsForVisibleItems
            .map { items.wrappedValue[$0.row % items.wrappedValue.count] }

        didScrollToItems(visibleItems)
    }

    // MARK: UICollectionViewDataSource

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {

        if isCarousel {
            effectiveItemCount
        } else {
            items.wrappedValue.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HostingCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as! HostingCollectionViewCell

        let item = items.wrappedValue[indexPath.row % items.wrappedValue.count]

        if let premade = prefetchedViewCache[item.hashValue] {
            cell.setupHostingView(premade: premade)
            prefetchedViewCache.removeValue(forKey: item.hashValue)
        } else {
            cell.setupHostingView(with: viewProvider(item))
        }

        return cell
    }

    // MARK: UICollectionViewDelegate

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {

        if case CongruentScrollingHStackLayout.selfSizingVariadicWidth = layout {

            let item = items.wrappedValue[indexPath.row]

            if let prefetch = prefetchedViewCache[item.hashValue] {
                prefetch.view.sizeToFit()
                return prefetch.view.bounds.size
            } else {
                let singleItem = UIHostingController(rootView: AnyView(viewProvider(item)))
                singleItem.view.sizeToFit()
                return singleItem.view.bounds.size
            }
        } else {
            if let itemSize {
                return itemSize
            } else {
                let s = itemSize(for: layout)
                itemSize = s
                return s
            }
        }
    }

    // MARK: item size

    private func itemSize(for layout: CongruentScrollingHStackLayout) -> CGSize {

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

        let insets = bottomInset + topInset
        let spacing = (_rows - 1) * itemSpacing

        return CGSize(
            width: width,
            height: (size.height - spacing - insets) / _rows
        )
    }

    // MARK: item width

    /// Precondition: columns > 0
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

        return (effectiveWidth - totalNegative) / columns
    }

    /// Precondition: minWidth > 0
    private func itemWidth(minWidth: CGFloat) -> CGFloat {

        precondition(minWidth > 0, "Given `minWidth` is less than or equal to 0")

        // Ensure that each item has a given minimum width
        let layout = collectionView.flowLayout
        var columns = CGFloat(Int((effectiveWidth - layout.sectionInset.horizontal) / minWidth))

        guard columns != 1 else { return itemWidth(columns: 1) }

        let preItemSpacing = (columns - 1) * layout.minimumInteritemSpacing

        let totalNegative = layout.sectionInset.horizontal + preItemSpacing

        // if adding negative space with current column count would result in column sizes < minWidth
        if columns * minWidth + totalNegative > bounds.width {
            columns -= 1
        }

        return itemWidth(columns: columns)
    }

    // required for tvOS
    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        false
    }

    // MARK: UICollectionViewDataSourcePrefetching

    // TODO: see if these actually do anything regarding prefetching images/View.onAppear
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {

        let fetchedItems: [Item] = indexPaths.map { items.wrappedValue[$0.row % items.wrappedValue.count] }

        for item in fetchedItems where !prefetchedViewCache.keys.contains(item.hashValue) {
            let premade = UIHostingController(rootView: AnyView(viewProvider(item)))
            prefetchedViewCache[item.hashValue] = premade
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {

        let fetchedItems: [Item] = indexPaths.map { items.wrappedValue[$0.row % items.wrappedValue.count] }

        for item in fetchedItems where !prefetchedViewCache.keys.contains(item.hashValue) {
            prefetchedViewCache.removeValue(forKey: item.hashValue)
        }
    }
}
