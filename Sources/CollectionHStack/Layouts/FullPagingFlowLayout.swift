#if canImport(UIKit)
import UIKit

class FullPagingFlowLayout: UICollectionViewFlowLayout {

    // necessary for cases when (total columns) % (columns per page) != 0
    private var isAtLast: Bool = false
    private var pageIndex: Int = 0

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {

        // allow scrolling to last page if proposed
        guard proposedContentOffset.x != collectionView!.contentSize.width - collectionView!.bounds.width else {

            if !isAtLast {
                isAtLast = true
                pageIndex += 1
            }

            return proposedContentOffset
        }

        guard pageIndex >= 0 else {
            pageIndex = 0
            return proposedContentOffset
        }

        let itemSpacing = collectionView!.flowLayout.minimumInteritemSpacing
        let leadingInset = collectionView!.flowLayout.sectionInset.left
        let pageSize = collectionView!.bounds.width - (leadingInset * 2) + itemSpacing

        // if not staying at last, then only decrementing
        if isAtLast {
            isAtLast = false
            pageIndex -= 1

            return CGPoint(
                x: pageIndex * pageSize,
                y: 0
            )
        }

        if velocity.x > 0 {
            pageIndex += 1

            if pageIndex * pageSize == collectionView!.contentSize.width - collectionView!.bounds.width {
                isAtLast = true
            }
        } else if velocity.x < 0 {
            pageIndex -= 1
        } else {
            let diff = abs(pageIndex * pageSize - proposedContentOffset.x)

            if diff > pageSize / 2 {
                if proposedContentOffset.x > pageIndex * pageSize {
                    pageIndex += 1

                    if pageIndex * pageSize == collectionView!.contentSize.width - collectionView!.bounds.width {
                        isAtLast = true
                    }
                } else {
                    pageIndex -= 1
                }
            }
        }

        return CGPoint(
            x: pageIndex * pageSize,
            y: 0
        )
    }
}

#endif
