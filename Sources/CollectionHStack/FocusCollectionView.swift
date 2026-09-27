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

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        let cells = entryFocusEnvironments()
        return cells.isEmpty ? super.preferredFocusEnvironments : cells
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let path = indexPath(containing: context.nextFocusedItem)
        if let path, let identity = identityAt(path) {
            hasFocused = true
            lastFocusedIdentity = identity
        }
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
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let edge = rightToLeft ? visibleBounds.maxX - layout.sectionInset.right : visibleBounds.minX + layout.sectionInset.left
        return (layout.layoutAttributesForElements(in: visibleBounds) ?? [])
            .filter { $0.representedElementCategory == .cell && $0.frame.intersects(visibleBounds) }
            .sorted {
                let left = abs((rightToLeft ? $0.frame.maxX : $0.frame.minX) - edge)
                let right = abs((rightToLeft ? $1.frame.maxX : $1.frame.minX) - edge)
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
