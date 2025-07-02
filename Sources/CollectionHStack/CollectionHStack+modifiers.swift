import SwiftUI

public extension CollectionHStack {

    func allowBouncing(_ value: Bool) -> Self {
        copy(modifying: \.allowBouncing, to: value)
    }

    func asCarousel() -> Self {
        copy(modifying: \.isCarousel, to: true)
    }

    func clipsToBounds(_ value: Bool) -> Self {
        copy(modifying: \.clipsToBounds, to: value)
    }

    func dataPrefix(_ prefix: Int?) -> Self {
        copy(modifying: \.dataPrefix, to: prefix)
    }

    // TODO: add once behavior defined
//    func didScrollToElements(_ action: @escaping ([Element]) -> Void) -> Self {
//        copy(modifying: \.didScrollToElements, to: action)
//    }

    func insets(_ insets: EdgeInsets) -> Self {
        copy(modifying: \.insets, to: insets)
    }

    func insets(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> Self {
        copy(modifying: \.insets, to: .init(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
    }

    func itemSpacing(_ spacing: CGFloat) -> Self {
        copy(modifying: \.itemSpacing, to: spacing)
    }

    func onReachedLeadingEdge(offset: CollectionHStackEdgeOffset = .offset(0), perform action: @escaping () -> Void) -> Self {
        copy(modifying: \.onReachedLeadingEdge, to: action)
            .copy(modifying: \.onReachedLeadingEdgeOffset, to: offset)
    }

    func onReachedTrailingEdge(offset: CollectionHStackEdgeOffset = .offset(0), perform action: @escaping () -> Void) -> Self {
        copy(modifying: \.onReachedTrailingEdge, to: action)
            .copy(modifying: \.onReachedTrailingEdgeOffset, to: offset)
    }

    func onPrefetchingElements(_ action: @escaping ([Element]) -> Void) -> Self {
        copy(modifying: \.onPrefetchingElements, to: action)
    }

    func onCancelPrefetchingElements(_ action: @escaping ([Element]) -> Void) -> Self {
        copy(modifying: \.onCancelPrefetchingElements, to: action)
    }

    func proxy(_ proxy: CollectionHStackProxy) -> Self {
        copy(modifying: \.proxy, to: proxy)
    }

    func scrollBehavior(_ scrollBehavior: CollectionHStackScrollBehavior) -> Self {
        copy(modifying: \.scrollBehavior, to: scrollBehavior)
    }
}
