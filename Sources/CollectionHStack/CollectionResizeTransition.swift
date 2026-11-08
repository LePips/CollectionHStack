import Foundation

/// SwiftUI's destination proposals and pixel-aligned intermediate proposals use
/// the same transition policy on UIKit and AppKit. Native adapters only supply
/// the displayed geometry and backing scale.
struct CollectionResizeTransition {
    private(set) var current: ItemSizeTransition?
    private var pending: ItemSizeTransition?
    private var needsTarget = true

    mutating func prepareForLayout() {
        needsTarget = true
        pending = nil
    }

    /// Returns true when the caller's last fitting-size result must be discarded.
    mutating func propose(
        width: CGFloat,
        displayedWidth: CGFloat,
        displayedItemSize: CGSize,
        displayedHeight: CGFloat,
        pixel: CGFloat,
        targetItemWidth: CGFloat?
    ) -> Bool {
        let tolerance = pixel / 2
        let isCurrentWidth = abs(width - displayedWidth) <= tolerance
        let completedResize = current.map {
            abs(displayedWidth - $0.targetWidth) <= tolerance && abs(width - $0.targetWidth) > tolerance
        } ?? false
        func transition() -> ItemSizeTransition? {
            guard displayedWidth.isFiniteAndPositive, abs(displayedWidth - width) > tolerance,
                  displayedHeight > 0, let targetItemWidth else { return nil }

            return ItemSizeTransition(
                sourceWidth: displayedWidth, targetWidth: width,
                sourceItemSize: displayedItemSize, targetItemWidth: targetItemWidth
            )
        }

        if needsTarget, isCurrentWidth, current?.progress(for: displayedWidth) != nil {
            needsTarget = false
            pending = nil
        } else if needsTarget || (!isCurrentWidth && (current == nil || completedResize)) {
            needsTarget = false
            current = transition()
            pending = nil
            return true
        } else if width == current?.targetWidth {
            pending = nil
        } else if let pending,
                  abs(width - pending.sourceWidth) + pixel < abs(pending.targetWidth - pending.sourceWidth)
        {
            // Retained subtrees may animate without another representable update.
            // Confirm a destination only when the next proposal returns toward
            // the source by more than pixel-alignment noise.
            current = pending
            self.pending = nil
            return true
        } else if !isCurrentWidth, pending == nil {
            pending = transition()
        }
        return false
    }

    mutating func apply(width: CGFloat, pixel: CGFloat) {
        guard let pending else { return }

        let direction: CGFloat = pending.targetWidth > pending.sourceWidth ? 1 : -1
        if (width - pending.targetWidth) * direction >= -pixel {
            self.pending = nil
        }
    }
}
