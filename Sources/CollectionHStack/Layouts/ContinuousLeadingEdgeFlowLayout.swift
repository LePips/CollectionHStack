#if canImport(UIKit)
import UIKit

/// Similar to `UICollectionLayoutSectionOrthogonalScrollingBehavior.continuousGroupLeadingBoundary`, where scrolling will align
/// along the leading boundary of a column minus the section's leading inset. If the proposed target content offset is the last column,
/// the last column will be aligned along its trailing edge with the section's trailing inset.
///
/// Column Center Scroll Behavior:
///   If the proposed target content offset is less than half of the leading columns's center, scrolling will
///   with that columns's leading edge. Otherwise, scrolling will align with the next columns's leading edge.
class ContinuousLeadingEdgeFlowLayout: UICollectionViewFlowLayout, ColumnAlignedLayout {

    var rows: Int = 1

    func scrollTo(index: Int, animated: Bool) {

        let proposedX = itemSize.width * index + minimumInteritemSpacing * max(index, 0)
        let lastWindow = collectionView!.contentSize.width - collectionView!.bounds.width
        let offset: CGFloat = min(proposedX, lastWindow)

        collectionView?.setContentOffset(.init(x: offset, y: 0), animated: animated)
    }

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {

        let targetRect = CGRect(
            x: proposedContentOffset.x,
            y: 0,
            width: collectionView!.bounds.size.width,
            height: collectionView!.bounds.size.height
        )

        let layoutAttributes = layoutAttributesForElements(in: targetRect)!

        // TODO: remove when allowing item sizes > collection view width
        guard layoutAttributes.count > 1 else { return proposedContentOffset }

        // allow scrolling to last element
        // floating point errors require rounding, nearing whole number is good enough
        let roundedProposedX = proposedContentOffset.x.rounded(.towardZero)
        let roundedLastWindow = (collectionView!.contentSize.width - collectionView!.bounds.width).rounded(.towardZero)

        if roundedProposedX.isEqual(to: roundedLastWindow) {
            return proposedContentOffset
        }

        let startOfColumnAttributes = layoutAttributes
            .chunks(ofCount: rows)
            .compactMap { $0.max(using: \.bounds.width) }

        // TODO: remove when allowing item sizes > collection view width
        guard startOfColumnAttributes.count > 1 else { return proposedContentOffset }

        let m: CGFloat = if proposedContentOffset.x > startOfColumnAttributes[0].center.x {
            startOfColumnAttributes[1].frame.minX
        } else {
            startOfColumnAttributes[0].frame.minX
        }

        let leadingInset = sectionInset.left

        return CGPoint(
            x: m - leadingInset,
            y: proposedContentOffset.y
        )
    }
}

#endif
