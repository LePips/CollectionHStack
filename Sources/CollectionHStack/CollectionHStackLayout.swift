import Foundation

public enum CollectionHStackLayout {

    case grid(columns: CGFloat, rows: Int, columnTrailingInset: CGFloat)
    /// Fits as many columns as possible without making items narrower than `columnWidth`.
    /// A `columnFraction` between zero and one also permits that much of the next
    /// column (for example, 0.5 allows 1, 1.5, 2, 2.5, ... visible columns).
    /// Zero or an invalid fraction uses whole columns. A container narrower than
    /// one minimum-width item shows one item fitted to the available content width.
    case minimumWidth(columnWidth: CGFloat, rows: Int, columnFraction: CGFloat = 0)
    case selfSizingSameSize(rows: Int)
    case selfSizingVariadicWidth(rows: Int)
}

extension CollectionHStackLayout: Equatable {
    public static func == (lhs: CollectionHStackLayout, rhs: CollectionHStackLayout) -> Bool {
        switch (lhs, rhs) {
        case let (.grid(lColumns, lRows, lInset), .grid(rColumns, rRows, rInset)):
            lColumns == rColumns && lRows == rRows && lInset == rInset
        case let (.minimumWidth(lWidth, lRows, lFraction), .minimumWidth(rWidth, rRows, rFraction)):
            lWidth == rWidth && lRows == rRows && lFraction == rFraction
        case let (.selfSizingSameSize(lRows), .selfSizingSameSize(rRows)):
            lRows == rRows
        case let (.selfSizingVariadicWidth(lRows), .selfSizingVariadicWidth(rRows)):
            lRows == rRows
        default:
            false
        }
    }
}
