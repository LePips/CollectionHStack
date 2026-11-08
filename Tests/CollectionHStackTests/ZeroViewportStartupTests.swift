#if os(iOS)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct ZeroViewportStartupTests {
    @Test(arguments: [100, 10000], [CGSize.zero, CGSize(width: 800, height: 0), CGSize(width: 0, height: 700)])
    func `inserting while attached without a viewport keeps cells virtualized`(count: Int, initialSize: CGSize) async throws {
        let layout = CollectionHStackLayout.grid(columns: 2, rows: 1, columnTrailingInset: 0)
        let data = Array(0 ..< count)
        var configuredIDs: [Int] = []
        let stack = UICollectionHStack(
            id: \Int.self, alignedLeadingElementID: nil, clipsToBounds: true,
            data: [Int](), dataPrefix: nil, insets: .init(), isCarousel: false,
            itemSpacing: 10, layout: layout,
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: .continuous
        ) { index in
            configuredIDs.append(index)
            return VStack(spacing: 7) {
                Color.blue
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Title \(index)").frame(height: 24)
            }
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 700))
        controller.view.addSubview(stack)
        stack.frame = CGRect(origin: .zero, size: initialSize)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()

        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.window != nil)
        #expect(collection.bounds.width == 0 || collection.bounds.height == 0)
        // The collection was initialized empty. This exercises the insertion
        // path while attached, rather than an unchanged initial snapshot.
        stack.update(newData: data, alignedLeadingElementID: nil, layout: layout)
        collection.layoutIfNeeded()
        #expect(configuredIDs.count <= 1, "At most a representative sizing probe is allowed before a viewport exists")

        let fitting = stack.fittingSize(forWidth: 800)
        stack.frame = CGRect(x: 0, y: 0, width: 800, height: fitting.height)
        stack.setNeedsLayout()
        stack.layoutIfNeeded()
        collection.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
        collection.layoutIfNeeded()

        #expect(collection.numberOfItems(inSection: 0) == count)
        #expect(!collection.visibleCells.isEmpty)
        #expect(collection.visibleCells.count < 10)
        #expect(configuredIDs.count < 20, "Startup work must remain bounded for both 100 and 10,000 items")
        #expect(configuredIDs.allSatisfy { data.indices.contains($0) })
        #expect(stack.index(id: count - 1) == count - 1)
        let first = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let last = try #require(collection.layoutAttributesForItem(at: IndexPath(item: count - 1, section: 0)))
        #expect(abs(first.size.width - 395) < 0.001)
        #expect(abs(first.size.height - (395 * 1.5 + 31)) < 0.001)
        #expect(last.size == first.size)
        #expect(abs(last.frame.minX - CGFloat(count - 1) * 405) < 0.001)

        let firstFrame = first.frame
        stack.update(newData: data, alignedLeadingElementID: nil, layout: layout)
        stack.layoutIfNeeded()
        collection.layoutIfNeeded()
        #expect(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == firstFrame)
        #expect(collection.numberOfItems(inSection: 0) == count)
        #expect(configuredIDs.count < 30)
    }
}
#endif
