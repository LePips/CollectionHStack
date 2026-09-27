import SwiftUI

/// Sizing rules shared by the UIKit and AppKit adapters. Native measurement and
/// flow-layout adjustments stay in the adapters; these metrics use the proposed width.
struct LayoutMetrics {
    let layout: CollectionHStackLayout
    let insets: EdgeInsets
    let itemSpacing: CGFloat

    var rows: Int {
        switch layout {
        case let .grid(_, rows, _), let .minimumWidth(_, rows, _),
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
            return itemWidth(for: availableWidth, columns: columns.positiveFinite(or: 1), trailingInset: trailingInset)
        case let .minimumWidth(minimum, _, fraction):
            let minimum = minimum.positiveFinite(or: 1)
            let contentWidth = nonnegativeFinite(availableWidth - insets.leading - insets.trailing)
            let wholeColumns = floor((contentWidth + spacing) / (minimum + spacing))
            var columns = fittingColumns(near: wholeColumns, minimum: minimum, availableWidth: availableWidth)
            if fraction.isFinite, fraction > 0, fraction < 1 {
                // A partial column uses a full gap and no trailing inset, just
                // like .grid. Solve separately instead of rounding whole columns.
                let fractionalContentWidth = availableWidth - insets.leading
                let fractionalColumns = floor((fractionalContentWidth - fraction * minimum) / (minimum + spacing)) + fraction
                columns = max(columns, fittingColumns(near: fractionalColumns, minimum: minimum, availableWidth: availableWidth))
            }
            let width = itemWidth(for: availableWidth, columns: columns)
            // Subtracting insets and dividing can undershoot by one floating-point
            // step even when the minimum-width geometry above fits exactly.
            return columns > 1 ? max(minimum, width) : width
        case .selfSizingSameSize, .selfSizingVariadicWidth:
            return nil
        }
    }

    private func itemWidth(for availableWidth: CGFloat, columns: CGFloat, trailingInset: CGFloat = 0) -> CGFloat {
        nonnegativeFinite((availableWidth - occupiedWidth(columns: columns, trailingInset: trailingInset)) / columns)
    }

    private func occupiedWidth(columns: CGFloat, trailingInset: CGFloat = 0) -> CGFloat {
        let integral = floor(columns) == columns
        let gaps = integral ? max(0, columns - 1) : floor(columns)
        return insets.leading + (integral ? insets.trailing : 0) + gaps * spacing + trailingInset
    }

    private func fittingColumns(near estimate: CGFloat, minimum: CGFloat, availableWidth: CGFloat) -> CGFloat {
        // A quotient can round either way at a breakpoint. Check neighboring
        // counts against their required geometry, without a tolerance that could
        // admit another column just below the breakpoint. This stays O(1).
        for columns in [estimate + 1, estimate, estimate - 1] where columns.isFinite && columns >= 1 {
            if occupiedWidth(columns: columns) + columns * minimum <= availableWidth {
                return columns
            }
        }
        return 1
    }

    func height(for itemSize: CGSize) -> CGFloat {
        nonnegativeFinite(CGFloat(rows) * itemSize.height + CGFloat(rows - 1) * spacing + insets.top + insets.bottom)
    }
}
