import Foundation

/// Reuses measurements for recent width proposals without assuming the whole cell
/// scales proportionally. Text, padding, and fixed-height content need a new layout
/// at each width, even when the cell also contains aspect-ratio artwork.
struct ItemSizeCache {
    private var widthSizes: [CGSize] = []
    private var naturalSize: CGSize?

    mutating func size(width: CGFloat?, measure: () -> CGSize) -> CGSize {
        guard let width else {
            if let naturalSize {
                return naturalSize
            }
            let measured = measure()
            let size = CGSize(width: nonnegativeFinite(measured.width), height: nonnegativeFinite(measured.height))
            naturalSize = size
            return size
        }
        guard width.isFiniteAndPositive else { return .zero }
        if let index = widthSizes.firstIndex(where: { $0.width == width }) {
            let size = widthSizes.remove(at: index)
            widthSizes.append(size)
            return size
        }
        let measured = measure()
        let size = CGSize(width: width, height: nonnegativeFinite(measured.height))
        if measured.width.isFiniteAndPositive, measured.height.isFiniteAndPositive {
            // SwiftUI may alternate proposals before committing a size. Keep a
            // small working set rather than retaining every live-resize width.
            if widthSizes.count == 8 {
                widthSizes.removeFirst()
            }
            widthSizes.append(size)
        }
        return size
    }
}
