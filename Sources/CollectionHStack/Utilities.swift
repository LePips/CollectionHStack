import DifferenceKit
import SwiftUI

// MARK: CGFloat/Int math

@_disfavoredOverload
func * (lhs: CGFloat, rhs: Int) -> CGFloat {
    lhs * CGFloat(rhs)
}

@_disfavoredOverload
func * (lhs: Int, rhs: CGFloat) -> CGFloat {
    CGFloat(lhs) * rhs
}

@_disfavoredOverload
func / (lhs: CGFloat, rhs: Int) -> CGFloat {
    lhs / CGFloat(rhs)
}

@_disfavoredOverload
func / (lhs: Int, rhs: CGFloat) -> CGFloat {
    CGFloat(lhs) / rhs
}

@_disfavoredOverload
func % (lhs: CGFloat, rhs: CGFloat) -> CGFloat {
    lhs.truncatingRemainder(dividingBy: rhs)
}

// MARK: Array

extension Array {

    @inlinable
    func max(using value: (Element) -> some Comparable) -> Element? {
        self.max(by: { value($0) < value($1) })
    }
}

// MARK: CGSize

func max(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
    let l = lhs.width * lhs.height
    let r = rhs.width * rhs.height

    if l > r {
        return lhs
    } else {
        return rhs
    }
}

func maxAbsDifference(_ lhs: CGSize, _ rhs: CGSize) -> CGFloat {
    let widthDiff = abs(lhs.width - rhs.width)
    let heightDiff = abs(lhs.height - rhs.height)

    return max(widthDiff, heightDiff)
}

// MARK: Collection

extension Collection {

    func prefixPositive(_ maxLength: Int) -> Self.SubSequence {
        guard maxLength > 0 else { return self[..<endIndex] }
        return prefix(maxLength)
    }
}

// MARK: - Sequence

extension Sequence {

    func chunks(ofCount count: Int) -> [[Element]] {

        guard count > 0 else { return [Array(self)] }

        var results: [[Element]] = []
        var c: [Element] = []
        var i = 0
        var iterator = makeIterator()

        while let e = iterator.next() {
            if i % count == 0, !c.isEmpty {
                results.append(c)
                c = []
            }

            c.append(e)

            i += 1
        }

        if !c.isEmpty {
            results.append(c)
        }

        return results
    }
}

// MARK: Int

extension Int: ContentEquatable, ContentIdentifiable {}

// MARK: UICollectionView

extension UICollectionView {

    var flowLayout: UICollectionViewFlowLayout {
        collectionViewLayout as! UICollectionViewFlowLayout
    }
}

// MARK: UIEdgeInsets

extension UIEdgeInsets {

    var horizontal: CGFloat {
        left + right
    }

    var vertical: CGFloat {
        top + bottom
    }
}

// MARK: View

extension View {

    func copy<Value>(modifying keyPath: WritableKeyPath<Self, Value>, to newValue: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = newValue
        return copy
    }
}
