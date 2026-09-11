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

#endif
