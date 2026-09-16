#if canImport(UIKit)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionHStackUpdateTests {
    @Test
    func collidingIDsAndStagedUpdatesKeepTheCorrectElements() async throws {
        var configured: [Int] = []
        let values = (0 ..< 8).map(CollidingID.init)
        let view = UICollectionHStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: true,
            data: values[2 ..< 6], dataPrefix: nil, didScrollToItems: { _ in },
            insets: .init(), isCarousel: false, itemSpacing: 10,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0),
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .offset(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .offset(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: .continuousLeadingEdge
        ) { element in
            configured.append(element.value)
            return Text("\(element.value)").frame(height: 40)
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        view.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.layoutIfNeeded()
        #expect(view.index(id: CollidingID(value: 2)) == 0)
        #expect(view.index(id: CollidingID(value: 5)) == 3)
        let next = [CollidingID(value: 5), CollidingID(value: 3), CollidingID(value: 7)]
        view.update(
            newData: next[...],
            alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        )
        try await Task.sleep(for: .milliseconds(150))
        let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.numberOfItems(inSection: 0) == 3)
        configured.removeAll()
        view.update(
            newData: next[...],
            alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        )
        #expect(!configured.isEmpty)
        #expect(Set(configured).isSubset(of: Set(next.map(\.value))))

        #expect(view.index(id: CollidingID(value: 2)) == nil)
        #expect(view.index(id: CollidingID(value: 5)) == 0)
        view.scrollTo(index: -1, animated: false)
        view.scrollTo(index: 100, animated: false)
        view.update(
            newData: [],
            alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        )
        #expect(collection.numberOfItems(inSection: 0) == 0)
    }

    @Test
    func carouselResolvesLatestContentAfterSliceAndPrefixChanges() throws {
        struct Value: Equatable {
            let id: Int
            let content: String
        }
        var prefetched: [Value] = []
        var cancelled: [Value] = []
        let initial = (0 ..< 5).map { Value(id: $0, content: "old") }
        let layout = CollectionHStackLayout.grid(columns: 2, rows: 1, columnTrailingInset: 0)
        let view = UICollectionHStack(
            id: \.id, alignedLeadingElementID: nil, clipsToBounds: true,
            data: initial[2...], dataPrefix: 2, didScrollToItems: { _ in },
            insets: .init(), isCarousel: true, itemSpacing: 10, layout: layout,
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .offset(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .offset(0),
            onPrefetchingElements: { prefetched = $0 },
            onCancelPrefetchingElements: { cancelled = $0 },
            proxy: .init(), scrollBehavior: .continuous
        ) { Text($0.content) }
        let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(view.collectionView(collection, numberOfItemsInSection: 0) == 100)
        #expect(view.index(id: 4) == nil)
        let paths = [IndexPath(item: 0, section: 0), IndexPath(item: 99, section: 0), IndexPath(item: 100, section: 0)]
        view.collectionView(collection, prefetchItemsAt: paths)
        #expect(prefetched == [initial[2], initial[3]])

        // Identical IDs, different source indices and content: no identity diff.
        let next = [Value(id: 2, content: "new 2"), Value(id: 3, content: "new 3")]
        view.update(newData: next[...], alignedLeadingElementID: nil, dataPrefix: 2, layout: layout)
        view.collectionView(collection, prefetchItemsAt: paths)
        view.collectionView(collection, cancelPrefetchingForItemsAt: paths)
        #expect(prefetched == next)
        #expect(cancelled == next)

        // Changing the prefix changes the carousel's modulo mapping.
        view.update(newData: next[...], alignedLeadingElementID: nil, dataPrefix: 1, layout: layout)
        view.collectionView(collection, prefetchItemsAt: paths)
        #expect(prefetched == [next[0], next[0]])
        #expect(view.index(id: 3) == nil)

        view.update(newData: [], alignedLeadingElementID: nil, layout: layout)
        #expect(view.collectionView(collection, numberOfItemsInSection: 0) == 0)
        view.collectionView(collection, prefetchItemsAt: paths)
        #expect(prefetched.isEmpty)
    }

    @Test
    func carouselGrowthDoesNotReadOrCopySourceElements() throws {
        let counter = ElementReadCounter()
        let values = CountingValues(counter: counter)
        let view = UICollectionHStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: true,
            data: values, dataPrefix: nil, didScrollToItems: { _ in },
            insets: .init(), isCarousel: true, itemSpacing: 10,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0),
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .offset(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .offset(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: .continuous
        ) { Text("\($0)") }
        let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(view.collectionView(collection, numberOfItemsInSection: 0) == 100)
        // Identity indexing touches only the three source elements, not 100 repetitions.
        #expect(counter.reads < 100)
        counter.reads = 0
        // An unattached, zero-sized collection is already at its trailing edge.
        view.scrollViewDidScroll(collection)
        #expect(view.collectionView(collection, numberOfItemsInSection: 0) == 200)
        #expect(counter.reads == 0)
    }

    @Test
    func hostingControllerSurvivesCellReuse() {
        let cell = HostingCollectionViewCell<Text>()
        cell.setup(view: Text("First"), id: 1)
        let host = cell.contentView.subviews.first
        cell.prepareForReuse()
        cell.setup(view: Text("Second"), id: 2)
        #expect(cell.contentView.subviews.count == 1)
        #expect(cell.contentView.subviews.first === host)
    }
}

private struct CollidingID: Hashable {
    let value: Int
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

private final class ElementReadCounter {
    var reads = 0
}

private struct CountingValues: RandomAccessCollection {
    let counter: ElementReadCounter
    let startIndex = 0
    let endIndex = 3
    func index(after i: Int) -> Int {
        i + 1
    }

    func index(before i: Int) -> Int {
        i - 1
    }

    subscript(index: Int) -> Int {
        counter.reads += 1
        return index
    }
}

#endif
