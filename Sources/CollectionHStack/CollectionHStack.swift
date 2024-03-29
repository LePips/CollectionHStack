import OrderedCollections
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

public struct CollectionHStack<Element: Hashable>: View {

    @State
    private var contentSize: CGSize = .zero

    @StateObject
    private var sizeObserver = SizeObserver()

    var allowBouncing: Binding<Bool>
    var allowScrolling: Binding<Bool>
    var clipsToBounds: Bool
    let data: Binding<OrderedSet<Element>>
    var dataPrefix: Binding<Int?>
    var didScrollToItems: ([Element]) -> Void
    var insets: EdgeInsets
    var isCarousel: Bool
    var itemSpacing: CGFloat
    let layout: CollectionHStackLayout
    var onReachedLeadingSide: () -> Void
    var onReachedLeadingSideOffset: CollectionHStackEdgeOffset
    var onReachedTrailingEdge: () -> Void
    var onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset
    var proxy: CollectionHStackProxy<Element>
    var scrollBehavior: CollectionHStackScrollBehavior
    let viewProvider: (Element) -> any View

    init(
        allowBouncing: Binding<Bool> = .constant(true),
        allowScrolling: Binding<Bool> = .constant(true),
        clipsToBounds: Bool = defaultClipsToBounds,
        data: Binding<OrderedSet<Element>>,
        dataPrefix: Binding<Int?> = .constant(nil),
        didScrollToItems: @escaping ([Element]) -> Void = { _ in },
        insets: EdgeInsets = .init(top: 0, leading: defaultHorizontalInset, bottom: 0, trailing: defaultHorizontalInset),
        isCarousel: Bool = false,
        itemSpacing: CGFloat = defaultItemSpacing,
        layout: CollectionHStackLayout,
        onReachedLeadingSide: @escaping () -> Void = {},
        onReachedLeadingSideOffset: CollectionHStackEdgeOffset = .columns(0),
        onReachedTrailingEdge: @escaping () -> Void = {},
        onReachedTrailingEdgeOffset: CollectionHStackEdgeOffset = .columns(0),
        proxy: CollectionHStackProxy<Element> = .init(),
        scrollBehavior: CollectionHStackScrollBehavior = .continuous,
        viewProvider: @escaping (Element) -> any View
    ) {
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
        self.onReachedLeadingSide = onReachedLeadingSide
        self.onReachedLeadingSideOffset = onReachedLeadingSideOffset
        self.onReachedTrailingEdge = onReachedTrailingEdge
        self.onReachedTrailingEdgeOffset = onReachedTrailingEdgeOffset
        self.proxy = proxy
        self.scrollBehavior = scrollBehavior
        self.viewProvider = viewProvider
    }

    public var body: some View {
        ZStack {
            SizeObserverView(sizeObserver: sizeObserver)
                .frame(height: 1)

            BridgeView(
                allowBouncing: allowBouncing,
                allowScrolling: allowScrolling,
                clipsToBounds: clipsToBounds,
                data: data,
                dataPrefix: dataPrefix,
                didScrollToItems: didScrollToItems,
                insets: insets,
                isCarousel: isCarousel,
                itemSpacing: itemSpacing,
                layout: layout,
                onReachedLeadingEdge: onReachedLeadingSide,
                onReachedLeadingEdgeOffset: onReachedLeadingSideOffset,
                onReachedTrailingEdge: onReachedTrailingEdge,
                onReachedTrailingEdgeOffset: onReachedTrailingEdgeOffset,
                proxy: proxy,
                scrollBehavior: scrollBehavior,
                sizeObserver: sizeObserver,
                viewProvider: viewProvider,
                sizeBinding: $contentSize
            )
            .frame(height: contentSize.height)
        }
    }
}
