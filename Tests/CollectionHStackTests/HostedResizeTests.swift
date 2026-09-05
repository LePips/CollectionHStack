#if os(iOS)
import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionHStackHostedResizeTests {
    private func findCollection(in view: UIView) -> UICollectionView? {
        if let view = view as? UICollectionView { return view }
        for subview in view.subviews {
            if let collection = findCollection(in: subview) { return collection }
        }
        return nil
    }

    @Test
    func hostedCollectionResizesAndStaysVirtualized() async throws {
        let host = UIHostingController(rootView: CollectionHStackResizeFixture())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 1000))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for width: CGFloat in [320, 414, 768, 1024, 1366, 506, 375, 1024] {
            window.frame.size = CGSize(width: width, height: 1000)
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 80_000_000)
            host.view.layoutIfNeeded()
            let collection = try #require(findCollection(in: host.view))
            #expect(collection.numberOfItems(inSection: 0) == 10000)
            let item = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let expectedWidth = (collection.bounds.width - 40 - 20) / 3
            #expect(abs(item.size.width - expectedWidth) <= 0.1)
            #expect(abs(item.size.height - (expectedWidth * 1.5)) <= 0.1)
            #expect(collection.visibleCells.count < 100)
        }
    }
}

private struct CollectionHStackResizeFixture: View {
    var body: some View {
        VStack(spacing: 0) {
            CollectionHStack(count: 10000, columns: 3) { _ in
                Color.blue.aspectRatio(2 / 3, contentMode: .fill)
            }
            .insets(horizontal: 20)
            .itemSpacing(10)
            Spacer(minLength: 0)
        }.ignoresSafeArea()
    }
}
#endif
