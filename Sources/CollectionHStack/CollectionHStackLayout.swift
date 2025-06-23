import Foundation

public enum CollectionHStackLayout {

    case grid(columns: CGFloat, rows: Int, columnTrailingInset: CGFloat)
    case minimumWidth(columnWidth: CGFloat, rows: Int)
    case selfSizingSameSize(rows: Int)
    case selfSizingVariadicWidth(rows: Int)
}
