import SwiftUI

#if os(tvOS)
private let defaultClipsToBounds = false
private let defaultHorizontalInset: CGFloat = 50
private let defaultItemSpacing: CGFloat = 40
#else
private let defaultClipsToBounds = true
private let defaultHorizontalInset: CGFloat = 15
private let defaultItemSpacing: CGFloat = 10
#endif

public struct CollectionHStack<
    Element,
    Data: Collection,
    ID: Hashable,
    Content: View
>: UIViewRepresentable where Data.Element == Element, Data.Index == Int {

    public typealias UIViewType = UICollectionHStack<Element, Data, ID, Content>

    let id: KeyPath<Element, ID>
    var allowBouncing: Bool
    var allowScrolling: Bool
    var clipsToBounds: Bool
    let data: Data
    var dataPrefix: Int?
    let didScrollToItems: ([Element]) -> Void
    var insets: EdgeInsets
    var isCarousel: Bool
    var itemSpacing: CGFloat
    let layout: CollectionHStackLayout
    var onReachedLeadingEdge: () -> Void
    var onReachedLeadingEdgeOffset: CollectionHStackEdgeOffset
    var onReachedTrailingEdge: () -> Void
    var onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset
    var proxy: CollectionHStackProxy
    var scrollBehavior: CollectionHStackScrollBehavior
    let viewProvider: (Element) -> Content

    init(
        id: KeyPath<Element, ID>,
        allowBouncing: Bool = true,
        allowScrolling: Bool = true,
        clipsToBounds: Bool = defaultClipsToBounds,
        data: Data,
        dataPrefix: Int? = nil,
        didScrollToItems: @escaping ([Element]) -> Void = { _ in },
        insets: EdgeInsets = .init(top: 0, leading: defaultHorizontalInset, bottom: 0, trailing: defaultHorizontalInset),
        isCarousel: Bool = false,
        itemSpacing: CGFloat = defaultItemSpacing,
        layout: CollectionHStackLayout,
        onReachedLeadingEdge: @escaping () -> Void = {},
        onReachedLeadingEdgeOffset: CollectionHStackEdgeOffset = .columns(0),
        onReachedTrailingEdge: @escaping () -> Void = {},
        onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset = .columns(0),
        proxy: CollectionHStackProxy = .init(),
        scrollBehavior: CollectionHStackScrollBehavior = .continuous,
        viewProvider: @escaping (Element) -> Content
    ) {
        self.id = id
        self.allowBouncing = allowBouncing
        self.allowScrolling = allowScrolling
        self.clipsToBounds = clipsToBounds
        self.data = data
        self.dataPrefix = dataPrefix
        self.didScrollToItems = didScrollToItems
        self.insets = insets
        self.isCarousel = isCarousel
        self.itemSpacing = itemSpacing
        self.layout = layout
        self.onReachedLeadingEdge = onReachedLeadingEdge
        self.onReachedLeadingEdgeOffset = onReachedLeadingEdgeOffset
        self.onReachedTrailingEdge = onReachedTrailingEdge
        self.onReachedTrailingEdgeOffset = onReachedTrailingEdgeOffset
        self.proxy = proxy
        self.scrollBehavior = scrollBehavior
        self.viewProvider = viewProvider
    }

    public func makeUIView(context: Context) -> UIViewType {
        UICollectionHStack(
            id: id,
            clipsToBounds: clipsToBounds,
            data: data,
            dataPrefix: dataPrefix,
            didScrollToItems: didScrollToItems,
            insets: insets,
            isCarousel: isCarousel,
            itemSpacing: itemSpacing,
            layout: layout,
            onReachedLeadingEdge: onReachedLeadingEdge,
            onReachedLeadingEdgeOffset: onReachedLeadingEdgeOffset,
            onReachedTrailingEdge: onReachedTrailingEdge,
            onReachedTrailingEdgeOffset: onReachedTrailingEdgeOffset,
            proxy: proxy,
            scrollBehavior: scrollBehavior,
            viewProvider: viewProvider
        )
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        view.update(
            newData: data,
            allowBouncing: allowBouncing,
            allowScrolling: context.environment.isScrollEnabled,
            dataPrefix: dataPrefix,
            layout: layout
        )
    }
}
