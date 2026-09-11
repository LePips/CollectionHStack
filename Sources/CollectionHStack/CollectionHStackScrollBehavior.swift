#if canImport(UIKit)
import UIKit
#endif

// TODO: care for item sizes > collection view width?
// TODO: care for item spacing which will make no other items appear on targetContentOffset?
// TODO: centered scroll behavior

// get contentoffset from scrollview begin dragging
// manually compute offset from item widths

public enum CollectionHStackScrollBehavior {

    case columnPaging
    case continuous
    case continuousLeadingEdge
    case fullPaging

    #if canImport(UIKit)
    var flowLayout: UICollectionViewFlowLayout {
        switch self {
        case .columnPaging:
            ColumnPagingFlowLayout()
        case .continuous:
            UICollectionViewFlowLayout()
        case .continuousLeadingEdge:
            ContinuousLeadingEdgeFlowLayout()
        case .fullPaging:
            FullPagingFlowLayout()
        }
    }
    #endif
}

#if canImport(UIKit)
// TODO: have leading vs centered be variable?

/// A `UICollectionViewFlowLayout` that aligns with a column of items
protocol ColumnAlignedLayout: UICollectionViewFlowLayout {

    /// Used for determining the correct column to align against
    var rows: Int { get set }
}

/// A `UICollectionViewFlowLayout` that will stride along columns
protocol ColumnStridableLayout: UICollectionViewFlowLayout {

    var step: Int { get set }
}

#endif
