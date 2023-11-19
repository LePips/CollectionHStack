import OrderedCollections
import SwiftUI

struct BridgeView<Item: Hashable>: UIViewRepresentable {

    typealias UIViewType = UICongruentScrollView<Item>

    let didReachTrailingSide: () -> Void
    let didReachTrailingSideOffset: CGFloat
    let didScrollToItems: ([Item]) -> Void
    let horizontalInset: CGFloat
    let items: Binding<OrderedSet<Item>>
    let itemSpacing: CGFloat
    let layout: CongruentScrollingHStackLayout
    let scrollBehavior: CongruentScrollingHStackScrollBehavior
    let sizeObserver: SizeObserver
    let viewProvider: (Item) -> any View

    func makeUIView(context: Context) -> UIViewType {
        UICongruentScrollView(
            didReachTrailingSide: didReachTrailingSide,
            didReachTrailingSideOffset: didReachTrailingSideOffset,
            didScrollToItems: didScrollToItems,
            horizontalInset: horizontalInset,
            items: items,
            itemSpacing: itemSpacing,
            layout: layout,
            scrollBehavior: scrollBehavior,
            sizeObserver: sizeObserver,
            viewProvider: viewProvider
        )
    }

    func updateUIView(_ view: UIViewType, context: Context) {
        view.updateItems(with: items)
    }
}