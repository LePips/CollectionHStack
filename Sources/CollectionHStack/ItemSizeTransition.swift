import Foundation

/// Interpolates measured endpoint sizes without revisiting the discrete column
/// count decisions between them. Both dimensions include the content's natural
/// layout, so fixed-height text and padding are not scaled with the artwork.
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

    func itemSize(at progress: CGFloat, targetSize: CGSize) -> CGSize {
        .init(
            width: sourceItemSize.width + (targetSize.width - sourceItemSize.width) * progress,
            height: sourceItemSize.height + (targetSize.height - sourceItemSize.height) * progress
        )
    }
}
