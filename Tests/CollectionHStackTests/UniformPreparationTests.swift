#if canImport(UIKit)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct UniformPreparationTests {
    @Test
    func `uniform preparation skips per item callbacks and variadic switching restores them`() throws {
        let stack = CountingStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: true,
            data: Array(0 ..< 10000), dataPrefix: nil, insets: .init(),
            isCarousel: false, itemSpacing: 10, layout: .grid(columns: 3, rows: 2, columnTrailingInset: 0),
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: .continuous,
            viewProvider: { VariableCard(index: $0) }
        )
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.contentInsetAdjustmentBehavior = .never
        func resize(_ width: CGFloat) {
            stack.frame = CGRect(x: 0, y: 0, width: width, height: stack.fittingSize(forWidth: width).height)
            stack.layoutIfNeeded()
            collection.layoutIfNeeded()
        }
        resize(900)
        stack.requests = 0
        for width: CGFloat in [700, 520, 830, 900] {
            resize(width)
        }
        // The shared preparation provider calls the Swift query once per prepare.
        // UIKit's expensive path would call it at least 10,000 times per resize.
        #expect(stack.requests < 100)
        let uniform = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        #expect(abs(uniform.frame.width - (900 - 20) / 3) < 0.01)
        stack.update(newData: Array(0 ..< 10000), alignedLeadingElementID: nil, layout: .selfSizingVariadicWidth(rows: 2))
        stack.requests = 0
        resize(880)
        #expect(stack.requests >= 10000)
        let first = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let second = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        #expect(first.frame.width != second.frame.width)
        stack.update(newData: Array(0 ..< 10000), alignedLeadingElementID: nil, layout: .grid(columns: 3, rows: 2, columnTrailingInset: 0))
        stack.requests = 0
        resize(900)
        #expect(stack.requests < 100)
    }
}

private final class CountingStack: UICollectionHStack<Int, [Int], Int, VariableCard> {
    var requests = 0
    override func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        requests += 1
        return super.collectionView(collectionView, layout: collectionViewLayout, sizeForItemAt: indexPath)
    }
}

private struct VariableCard: View {
    let index: Int
    var body: some View {
        Text(String(repeating: "W", count: 3 + index % 5)).frame(height: 40)
    }
}
#endif
