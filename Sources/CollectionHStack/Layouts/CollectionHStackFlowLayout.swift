#if canImport(UIKit)
import UIKit

class CollectionHStackFlowLayout: UICollectionViewFlowLayout {
    /// The collection renders outside its logical viewport when clipping is disabled.
    /// Paging still uses the original viewport, excluding this extra rendering area.
    var renderingInsets: UIEdgeInsets = .zero

    func viewportBounds(at offset: CGPoint) -> CGRect {
        CGRect(origin: offset, size: collectionView?.bounds.size ?? .zero).inset(by: renderingInsets)
    }
}
#endif
