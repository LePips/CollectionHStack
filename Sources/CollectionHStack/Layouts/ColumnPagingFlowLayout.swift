#if canImport(UIKit)
import UIKit

class ColumnPagingFlowLayout: UICollectionViewFlowLayout, ColumnAlignedLayout {

    var rows: Int = 1

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {

        let targetRect = CGRect(
            x: collectionView!.contentOffset.x,
            y: 0,
            width: collectionView!.bounds.size.width,
            height: collectionView!.bounds.size.height
        )

        let layoutAttributes = layoutAttributesForElements(in: targetRect)!

        // TODO: remove when allowing item sizes > collection view width
        guard layoutAttributes.count > 1 else { return proposedContentOffset }

        let startOfColumnAttributes = layoutAttributes
            .chunks(ofCount: rows)
            .compactMap { $0.max(using: \.bounds.width) }

        // TODO: remove when allowing item sizes > collection view width
        guard startOfColumnAttributes.count > 1 else { return proposedContentOffset }

        let m: CGFloat = if velocity.x > 0 {
            startOfColumnAttributes[1].frame.minX
        } else if velocity.x < 0 {
            startOfColumnAttributes[0].frame.minX
        } else {
            if proposedContentOffset.x > layoutAttributes[0].center.x {
                startOfColumnAttributes[1].frame.minX
            } else {
                startOfColumnAttributes[0].frame.minX
            }
        }

        let leadingInset = collectionView!.flowLayout.sectionInset.left

        return CGPoint(
            x: m - leadingInset,
            y: proposedContentOffset.y
        )
    }
}

#endif
