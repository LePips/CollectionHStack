import Foundation

/// Interpolates item widths without revisiting discrete column-count decisions.
/// Height must be measured at that width: wrapping text and conditional layouts
/// can change height discontinuously between the measured endpoints.
struct ItemSizeTransition {
    /// How far beyond either endpoint, as a fraction of the transition, a width
    /// still follows it.
    static let overshoot: CGFloat = 0.25

    let sourceWidth: CGFloat
    let targetWidth: CGFloat
    let sourceItemSize: CGSize
    let targetItemWidth: CGFloat

    func progress(for width: CGFloat) -> CGFloat? {
        guard sourceWidth != targetWidth, width.isFinite else { return nil }

        // Springs can overshoot either endpoint, particularly after a reversal.
        // Follow their progress instead of falling back to a different column count.
        // A distant width is not part of this transition, such as a destination
        // probe after a short retarget: extrapolating to it can produce sizes far
        // outside both layouts, or below zero.
        let progress = (width - sourceWidth) / (targetWidth - sourceWidth)
        guard progress >= -Self.overshoot, progress <= 1 + Self.overshoot else { return nil }

        return progress
    }

    func itemWidth(at progress: CGFloat) -> CGFloat {
        sourceItemSize.width + (targetItemWidth - sourceItemSize.width) * progress
    }
}
