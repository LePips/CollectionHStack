import SwiftUI

#if canImport(Broadcast)
import Broadcast
#endif

public extension CollectionHStack {

    /// Tracks the ID of the first element in the last column to settle against the leading edge.
    ///
    /// The binding retains its last settled ID while scrolling. Tracking is available
    /// for `.continuousLeadingEdge` and `.columnPaging`. It is set to `nil` when the
    /// collection is empty, the scroll behavior does not align columns, or no column
    /// is exactly leading-aligned. Assigning to the binding does not scroll the
    /// collection; use a ``CollectionHStackProxy`` for that.
    func alignedLeadingElement(id: Binding<ID?>) -> Self {
        copy(modifying: \.alignedLeadingElementID, to: id)
    }

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

    /// Enables built-in diagnostics. Disabled by default to avoid retaining logs
    /// during normal scrolling and resizing.
    func tracingEnabled(_ enabled: Bool = true) -> Self {
        copy(modifying: \.traceLog, to: enabled ? .default : .disabled)
    }

    #if canImport(Broadcast)
    /// Routes CollectionHStack's structured diagnostics through the supplied Broadcast log.
    ///
    /// Tracing is disabled by default. Use ``CollectionHStackDiagnostics/log`` for
    /// built-in destinations, or inject app-owned destinations to combine these
    /// records with the rest of the app's diagnostics.
    func traced(using log: Log) -> Self {
        copy(modifying: \.traceLog, to: CollectionHStackTrace(log: log))
    }
    #endif
}
