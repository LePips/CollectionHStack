#if canImport(UIKit)
import UIKit

@MainActor
protocol CollectionHStackItemSizeProvider: AnyObject {
    func uniformItemSize(in collectionView: UICollectionView) -> CGSize?
}

class CollectionHStackFlowLayout: UICollectionViewFlowLayout {
    /// The collection renders outside its logical viewport when clipping is disabled.
    /// Paging still uses the original viewport, excluding this extra rendering area.
    var renderingInsets: UIEdgeInsets = .zero

    override func prepare() {
        // Uniform rows need one size per preparation, not a delegate call for
        // every element. Variadic rows keep UIKit's individual-size path.
        if let collectionView,
           collectionView.bounds.width.isFiniteAndPositive,
           let provider = collectionView.delegate as? CollectionHStackItemSizeProvider,
           let size = provider.uniformItemSize(in: collectionView), itemSize != size
        {
            itemSize = size
        }
        super.prepare()
    }

    func viewportBounds(at offset: CGPoint) -> CGRect {
        CGRect(origin: offset, size: collectionView?.bounds.size ?? .zero).inset(by: renderingInsets)
    }
}
#endif
