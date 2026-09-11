import SwiftUI

/// Sizing rules shared by the UIKit and AppKit adapters. Native measurement and
/// flow-layout adjustments stay in the adapters; these metrics use the proposed width.
struct LayoutMetrics {
    let layout: CollectionHStackLayout
    let insets: EdgeInsets
    let itemSpacing: CGFloat

    var rows: Int {
        switch layout {
        case let .grid(_, rows, _), let .minimumWidth(_, rows),
             let .selfSizingSameSize(rows), let .selfSizingVariadicWidth(rows):
            max(1, rows)
        }
    }

    var spacing: CGFloat {
        nonnegativeFinite(itemSpacing)
    }

    /// Nil requests the content's natural size. Fractional columns expose part of
    /// the next column, so only whole-column layouts consume the trailing inset.
    func itemWidth(for availableWidth: CGFloat) -> CGFloat? {
        guard availableWidth.isFiniteAndPositive else { return 0 }
        switch layout {
        case let .grid(columns, _, trailingInset):
            let columns = columns.positiveFinite(or: 1)
            let integral = floor(columns) == columns
            let gaps = integral ? max(0, columns - 1) : floor(columns)
            let occupied = insets.leading + (integral ? insets.trailing : 0) + gaps * spacing + trailingInset
            return nonnegativeFinite((availableWidth - occupied) / columns)
        case let .minimumWidth(minimum, _):
            let minimum = minimum.positiveFinite(or: 1)
            let contentWidth = nonnegativeFinite(availableWidth - insets.leading - insets.trailing)
            let columns = max(1, floor((contentWidth + spacing) / (minimum + spacing)))
            return nonnegativeFinite((contentWidth - (columns - 1) * spacing) / columns)
        case .selfSizingSameSize, .selfSizingVariadicWidth:
            return nil
        }
    }

    func height(for itemSize: CGSize) -> CGFloat {
        nonnegativeFinite(CGFloat(rows) * itemSize.height + CGFloat(rows - 1) * spacing + insets.top + insets.bottom)
    }
}
