import Foundation

public enum CollectionHStackLayout {

    case grid(columns: CGFloat, rows: Int, columnTrailingInset: CGFloat)
    case minimumWidth(columnWidth: CGFloat, rows: Int)
    case selfSizingSameSize(rows: Int)
    case selfSizingVariadicWidth(rows: Int)
}

extension CollectionHStackLayout: Equatable {
    public static func == (lhs: CollectionHStackLayout, rhs: CollectionHStackLayout) -> Bool {
        switch (lhs, rhs) {
        case let (.grid(lColumns, lRows, lInset), .grid(rColumns, rRows, rInset)):
            lColumns == rColumns && lRows == rRows && lInset == rInset
        case let (.minimumWidth(lWidth, lRows), .minimumWidth(rWidth, rRows)):
            lWidth == rWidth && lRows == rRows
        case let (.selfSizingSameSize(lRows), .selfSizingSameSize(rRows)):
            lRows == rRows
        case let (.selfSizingVariadicWidth(lRows), .selfSizingVariadicWidth(rRows)):
            lRows == rRows
        default:
            false
        }
    }
}
