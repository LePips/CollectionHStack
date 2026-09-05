import Foundation
import UIKit

public class CollectionHStackProxy: ObservableObject {

    weak var collectionView: _UICollectionHStack?

    public init() {
        self.collectionView = nil
    }

    public func scrollTo(index: Int, animated: Bool = true) {
        collectionView?.scrollTo(index: index, animated: animated)
    }

    /// Scrolls to the element with the given `id.hashValue` if
    /// it exists in the current `CollectionHStack`.
    ///
    /// This `id` must match the `id` used to create the `CollectionHStack`.
    public func scrollTo(id: some Hashable, animated: Bool = true) {
        guard let index = collectionView?.index(id: id) else { return }
        scrollTo(index: index, animated: animated)
    }

    /// Remeasures item content and redraws the collection's items.
    ///
    /// Call this after changing content that affects item size. The collection derives
    /// its resize proportions from the new measurement; no sizing values are required.
    public func redraw() {
        objectWillChange.send()
        collectionView?.snapshotReload()
    }
}
