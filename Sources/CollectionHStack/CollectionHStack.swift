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
    var alignedLeadingElementID: Binding<ID?>?
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
    var onPrefetchingElements: ([Element]) -> Void
    var onCancelPrefetchingElements: ([Element]) -> Void
    var proxy: CollectionHStackProxy
    var scrollBehavior: CollectionHStackScrollBehavior
    var traceLog: CollectionHStackTrace
    let viewProvider: (Element) -> Content

    init(
        id: KeyPath<Element, ID>,
        alignedLeadingElementID: Binding<ID?>? = nil,
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
        onPrefetchingElements: @escaping ([Element]) -> Void = { _ in },
        onCancelPrefetchingElements: @escaping ([Element]) -> Void = { _ in },
        proxy: CollectionHStackProxy = .init(),
        scrollBehavior: CollectionHStackScrollBehavior = .continuous,
        traceLog: CollectionHStackTrace = .disabled,
        viewProvider: @escaping (Element) -> Content
    ) {
        self.id = id
        self.alignedLeadingElementID = alignedLeadingElementID
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
        self.onPrefetchingElements = onPrefetchingElements
        self.onCancelPrefetchingElements = onCancelPrefetchingElements
        self.proxy = proxy
        self.scrollBehavior = scrollBehavior
        self.traceLog = traceLog
        self.viewProvider = viewProvider
    }

    public func makeUIView(context: Context) -> UIViewType {
        UICollectionHStack(
            id: id,
            alignedLeadingElementID: alignedLeadingElementID,
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
            onPrefetchingElements: onPrefetchingElements,
            onCancelPrefetchingElements: onCancelPrefetchingElements,
            proxy: proxy,
            scrollBehavior: scrollBehavior,
            traceLog: traceLog,
            viewProvider: viewProvider
        )
    }

    public func updateUIView(_ view: UIViewType, context: Context) {
        view.update(
            newData: data,
            alignedLeadingElementID: alignedLeadingElementID,
            allowBouncing: allowBouncing,
            allowScrolling: context.environment.isScrollEnabled,
            dataPrefix: dataPrefix,
            layout: layout,
            traceLog: traceLog,
            insets: insets,
            itemSpacing: itemSpacing,
            viewProvider: viewProvider
        )
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIViewType,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return uiView.fittingSize(forWidth: width)
    }
}
