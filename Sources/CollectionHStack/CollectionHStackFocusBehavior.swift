#if os(tvOS)
/// Chooses which item receives focus when focus enters a collection on tvOS.
/// Navigation between items is always handled by the UIKit focus engine.
public struct CollectionHStackFocusBehavior: Equatable, Sendable {
    public enum Initial: Equatable, Sendable {
        /// Use UIKit's spatial choice, based on the incoming focus direction.
        case automatic
        /// Prefer the visible item nearest the collection's leading content edge.
        case leading
    }

    public enum Returning: Equatable, Sendable {
        /// Use UIKit's spatial choice again.
        case automatic
        /// Prefer the currently leading item, without returning to the start of the data.
        case leading
        /// Restore the last focused element by identity, scrolling to it if needed.
        /// If it was removed, fall back to the currently leading item.
        case lastFocused
    }

    public var initial: Initial
    public var returning: Returning

    public init(initial: Initial = .automatic, returning: Returning = .automatic) {
        self.initial = initial
        self.returning = returning
    }
}

public extension CollectionHStack {
    /// Controls first and subsequent focus entry using UIKit on tvOS.
    ///
    /// Content must contain a focusable view, such as a `Button` or a view with
    /// `.focusable()`. Its actions and focus appearance remain unchanged. Leading
    /// preference uses the current viewport and section insets, with the top item
    /// winning ties in a multirow column. Nonfocusable content is skipped by UIKit.
    /// History lasts for the lifetime of this collection view and survives redraws
    /// and data reordering. The default for both entry policies is `.automatic`.
    /// Wrap the collections and surrounding controls in `CollectionHStackFocusScope`
    /// to apply these preferences to directional entry, including offscreen rows.
    func focusBehavior(
        initial: CollectionHStackFocusBehavior.Initial = .automatic,
        returning: CollectionHStackFocusBehavior.Returning = .automatic
    ) -> Self {
        copy(modifying: \.focusBehavior, to: .init(initial: initial, returning: returning))
    }
}
#endif
