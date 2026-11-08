import SwiftUI

/// Shared measurement lifetime and cache policy for both native adapters.
/// A nil width measures natural content; variadic layouts cache those sizes by ID.
@MainActor
final class CollectionItemSizing<Content: View> {
    private var cache = ItemSizeCache()
    private var measurer = ContentMeasurer<Content>()

    func invalidate() {
        cache = ItemSizeCache()
        measurer = ContentMeasurer()
    }

    func size(width: CGFloat?, environment: EnvironmentValues? = nil, reusingContent: Bool = false, content: () -> (Content, AnyHashable)) -> CGSize {
        cache.size(width: width) {
            if reusingContent, let size = measurer.size(reusingContentAt: width) {
                return size
            }
            let (content, identity) = content()
            return measure(content, identity: identity, width: width, environment: environment)
        }
    }

    func measure(_ content: Content, identity: AnyHashable, width: CGFloat?, environment: EnvironmentValues? = nil) -> CGSize {
        measurer.size(of: content, identity: identity, width: width, environment: environment)
    }
}
