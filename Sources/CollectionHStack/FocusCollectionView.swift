#if os(tvOS)
import UIKit

/// Keeps focus policy at the UIKit boundary, including focusable SwiftUI descendants
/// inside cells (which are deliberately not themselves focusable).
final class FocusCollectionView: UICollectionView {
    var behavior = CollectionHStackFocusBehavior()

    var identityAt: (IndexPath) -> AnyHashable? = { _ in nil }
    var indexPathForIdentity: (AnyHashable) -> IndexPath? = { _ in nil }

    private var hasFocused = false
    private var lastFocusedIdentity: AnyHashable?
    private var isResolvingEntry = false
    private weak var focusedCell: UICollectionViewCell?

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        let cells = entryFocusEnvironments()
        return cells.isEmpty ? super.preferredFocusEnvironments : cells
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let path = indexPath(containing: context.nextFocusedItem)
        focusedCell = path.flatMap { cellForItem(at: $0) }
        super.didUpdateFocus(in: context, with: coordinator)
        if let path, let identity = identityAt(path) {
            hasFocused = true
            lastFocusedIdentity = identity
        }
        guard let path else { return }

        // UIKit may not request a scroll when the focused child is already visible.
        coordinator.addCoordinatedAnimations {
            guard self.focusedCell.flatMap({ self.indexPath(for: $0) }) == path else { return }

            let offset = self.contentOffset(revealingFocusedCellAt: self.contentOffset)
            if offset != self.contentOffset {
                self.setContentOffset(offset, animated: false)
            }
        } completion: {
            (self.collectionViewLayout as? FullPagingFlowLayout)?.synchronizePageWithContentOffset()
        }
    }

    func contentOffset(revealingFocusedCellAt proposedOffset: CGPoint) -> CGPoint {
        guard isScrollEnabled,
              let focusedCell, let path = indexPath(for: focusedCell),
              let layout = collectionViewLayout as? CollectionHStackFlowLayout,
              let attributes = layout.layoutAttributesForItem(at: path) else { return proposedOffset }

        // Hosted controls can be smaller than their cell. Keep the whole cell
        // inside the content viewport. Section insets include rendering overflow.
        let viewport = CGRect(origin: proposedOffset, size: bounds.size)
            .inset(by: adjustedContentInset)
            .inset(by: layout.sectionInset)
        let frame = attributes.frame
        guard viewport.width.isFiniteAndPositive, frame.width <= viewport.width else { return proposedOffset }

        var offset = proposedOffset
        if frame.minX < viewport.minX {
            offset.x += frame.minX - viewport.minX
        } else if frame.maxX > viewport.maxX {
            offset.x += frame.maxX - viewport.maxX
        } else {
            return proposedOffset
        }
        let minimum = -adjustedContentInset.left
        let maximum = max(minimum, contentSize.width - bounds.width + adjustedContentInset.right)
        offset.x = offset.x.clamped(to: minimum ... maximum)
        if layout is ColumnAlignedLayout, offset.x > minimum, offset.x < maximum {
            // Preserve column alignment, but only among offsets that reveal the cell.
            let minimumVisibleOffset = proposedOffset.x + frame.maxX - viewport.maxX
            let maximumVisibleOffset = proposedOffset.x + frame.minX - viewport.minX
            let candidates = (layout.layoutAttributesForElements(in: layout.viewportBounds(at: offset)) ?? [])
                .filter { $0.representedElementCategory == .cell }
                .map { $0.frame.minX - layout.sectionInset.left }
                .filter { $0 >= max(minimum, minimumVisibleOffset) && $0 <= min(maximum, maximumVisibleOffset) }
            if let nearest = candidates.min(by: { abs($0 - offset.x) < abs($1 - offset.x) }) {
                offset.x = nearest
            }
        }
        return offset
    }

    func entryFocusEnvironments() -> [UIFocusEnvironment] {
        guard !isResolvingEntry else { return [] }

        isResolvingEntry = true
        defer { isResolvingEntry = false }
        let identities = preferredEntryIdentities()
        if let first = identities.first, let path = indexPathForIdentity(first),
           let attributes = collectionViewLayout.layoutAttributesForItem(at: path),
           !attributes.frame.intersects(bounds.inset(by: adjustedContentInset))
        {
            scrollToItem(at: path, at: .centeredHorizontally, animated: false)
            layoutIfNeeded()
        }
        return identities.compactMap { indexPathForIdentity($0) }.compactMap { cellForItem(at: $0) }
    }

    func preferredEntryIdentities() -> [AnyHashable] {
        if !hasFocused {
            return behavior.initial == .leading ? leadingIdentities() : []
        }
        switch behavior.returning {
        case .automatic:
            return []
        case .leading:
            return leadingIdentities()
        case .lastFocused:
            let leading = leadingIdentities()
            guard let lastFocusedIdentity, indexPathForIdentity(lastFocusedIdentity) != nil else { return leading }

            return [lastFocusedIdentity] + leading.filter { $0 != lastFocusedIdentity }
        }
    }

    private func leadingIdentities() -> [AnyHashable] {
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else { return [] }

        let visibleBounds = bounds.inset(by: adjustedContentInset)
        let edge = visibleBounds.minX + layout.sectionInset.left
        return (layout.layoutAttributesForElements(in: visibleBounds) ?? [])
            .filter { $0.representedElementCategory == .cell && $0.frame.intersects(visibleBounds) }
            .sorted {
                let left = abs($0.frame.minX - edge)
                let right = abs($1.frame.minX - edge)
                if abs(left - right) > 0.5 {
                    return left < right
                }
                if $0.frame.minY != $1.frame.minY {
                    return $0.frame.minY < $1.frame.minY
                }
                return $0.indexPath.item < $1.indexPath.item
            }
            .compactMap { identityAt($0.indexPath) }
    }

    func indexPath(containing item: UIFocusItem?) -> IndexPath? {
        var environment: UIFocusEnvironment? = item
        while let current = environment, current !== self {
            if let cell = current as? UICollectionViewCell, let path = indexPath(for: cell) {
                return path
            }
            environment = current.parentFocusEnvironment
        }
        return nil
    }
}

#endif
