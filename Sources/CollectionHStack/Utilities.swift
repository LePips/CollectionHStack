import SwiftUI

// MARK: Comparable

extension Comparable {

    @inlinable
    func clamped(to limits: ClosedRange<Self>) -> Self {
        Swift.min(limits.upperBound, Swift.max(limits.lowerBound, self))
    }
}

// MARK: FloatingPoint

extension BinaryFloatingPoint {

    @inlinable
    var isFiniteAndPositive: Bool {
        isFinite && self > 0
    }

    @inlinable
    func positiveFinite(or fallback: Self) -> Self {
        isFiniteAndPositive ? self : fallback
    }
}

/// Layout dimensions must be finite and nonnegative; invalid values become zero.
@inlinable
func nonnegativeFinite(_ value: CGFloat) -> CGFloat {
    value.isFinite ? max(value, 0) : 0
}

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

// MARK: Collection

extension Collection {

    @inlinable
    var isNotEmpty: Bool {
        !isEmpty
    }

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
            if i % count == 0, c.isNotEmpty {
                results.append(c)
                c = []
            }

            c.append(e)

            i += 1
        }

        if c.isNotEmpty {
            results.append(c)
        }

        return results
    }
}

#if canImport(UIKit)

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

#endif

// MARK: View

extension View {

    func copy<Value>(modifying keyPath: WritableKeyPath<Self, Value>, to newValue: Value) -> Self {
        var copy = self
        copy[keyPath: keyPath] = newValue
        return copy
    }
}
