#if os(iOS)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct OverflowVisibilityTests {
    @Test(arguments: 0 ..< 4, [false, true])
    func `unclipped rows keep cells visible beyond their layout bounds`(
        behaviorIndex: Int,
        leadingOverflow: Bool
    ) async throws {
        let behavior: CollectionHStackScrollBehavior = [.continuous, .continuousLeadingEdge, .columnPaging, .fullPaging][behaviorIndex]
        let configuration = CollectionHStack(
            uniqueElements: Array(0 ..< 100),
            layout: .grid(columns: 3, rows: 1, columnTrailingInset: 0)
        ) { item in
            Color.blue.overlay(Text("\(item)")).frame(height: 100)
        }
        .clipsToBounds(false)
        .insets(horizontal: 16)
        .scrollBehavior(behavior)
        .contentInsetAdjustmentBehavior(.never)

        let stack = UICollectionHStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: false,
            data: configuration.data, dataPrefix: nil,
            insets: configuration.insets, isCarousel: false, itemSpacing: configuration.itemSpacing,
            layout: configuration.layout,
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: configuration.scrollBehavior,
            viewProvider: configuration.viewProvider
        )
        stack.configure(configuration)

        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 644))
        window.rootViewController = controller
        controller.view.addSubview(stack)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let width = window.bounds.width - 84
        let fitted = stack.fittingSize(forWidth: width)
        stack.frame = CGRect(x: leadingOverflow ? 84 : 0, y: 100, width: width, height: fitted.height)
        controller.view.layoutIfNeeded()
        stack.layoutIfNeeded()
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.layoutIfNeeded()

        let target = IndexPath(item: 8, section: 0)
        let attributes = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: target))
        collection.contentOffset.x = leadingOverflow
            ? attributes.frame.maxX + 20 - 84
            : attributes.frame.minX - width - 20
        collection.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let frameInStack = collection.convert(attributes.frame, to: stack)
        #expect(!frameInStack.intersects(stack.bounds))
        #expect(collection.convert(attributes.frame, to: window).intersects(window.bounds))
        let cell = try #require(collection.cellForItem(at: target), "The card is still visible outside the row's safe content bounds")
        #expect(cell.window === window)
        #expect(!cell.isHidden)
        #expect(collection.visibleCells.count < 10)

        // Turning clipping back on must restore the ordinary viewport.
        stack.configure(configuration.clipsToBounds(true))
        stack.layoutIfNeeded()
        collection.layoutIfNeeded()
        #expect(collection.frame == stack.bounds)
        let isHiddenWhenClipped = collection.cellForItem(at: target)?.isHidden ?? true
        #expect(isHiddenWhenClipped)
        stack.configure(configuration)
        stack.layoutIfNeeded()
        collection.layoutIfNeeded()
        let isVisibleWhenUnclipped = collection.cellForItem(at: target)?.isHidden == false
        #expect(isVisibleWhenUnclipped)

        // The extra rendering area must not change card size or scroll alignment.
        stack.scrollTo(index: 8, animated: false)
        collection.layoutIfNeeded()
        let aligned = try #require(collection.cellForItem(at: target))
        let alignedFrame = collection.convert(aligned.frame, to: stack)
        #expect(abs(alignedFrame.width - (width - 52) / 3) < 0.001)
        if behavior == .continuousLeadingEdge || behavior == .columnPaging {
            #expect(abs(alignedFrame.minX - 16) < 0.001)
            let proposed = CGPoint(x: collection.contentOffset.x + alignedFrame.width * 0.8, y: 0)
            let snapped = collection.collectionViewLayout.targetContentOffset(
                forProposedContentOffset: proposed, withScrollingVelocity: CGPoint(x: 1, y: 0)
            )
            stack.configure(configuration.clipsToBounds(true))
            stack.layoutIfNeeded()
            stack.scrollTo(index: 8, animated: false)
            collection.layoutIfNeeded()
            let ordinaryProposed = CGPoint(x: collection.contentOffset.x + alignedFrame.width * 0.8, y: 0)
            let ordinarySnap = collection.collectionViewLayout.targetContentOffset(
                forProposedContentOffset: ordinaryProposed, withScrollingVelocity: CGPoint(x: 1, y: 0)
            )
            #expect(abs(snapped.x - ordinarySnap.x) < 0.001)
            stack.configure(configuration)
            stack.layoutIfNeeded()
        } else {
            #expect(abs(alignedFrame.midX - width / 2) < 0.001)
        }
        if behavior == .fullPaging {
            let page = width - 32 + 10
            let snapped = collection.collectionViewLayout.targetContentOffset(
                forProposedContentOffset: CGPoint(x: page * 0.8, y: 0), withScrollingVelocity: CGPoint(x: 1, y: 0)
            )
            #expect(abs(snapped.x - page) < 0.001)
        }

        stack.scrollTo(index: 99, animated: false)
        collection.layoutIfNeeded()
        let last = try #require(collection.cellForItem(at: IndexPath(item: 99, section: 0)))
        #expect(abs(collection.convert(last.frame, to: stack).maxX - (width - 16)) < 0.001)

        stack.snapshotReload()
        stack.layoutIfNeeded()
        let snapshot = try #require(stack.subviews.first { $0 !== collection })
        #expect(snapshot.frame == collection.frame)

        // A clipping ancestor remains a hard boundary, including for hidden rows.
        let boundary = UIView(frame: stack.frame)
        boundary.clipsToBounds = true
        controller.view.addSubview(boundary)
        boundary.addSubview(stack)
        stack.frame = boundary.bounds
        stack.setNeedsLayout()
        stack.layoutIfNeeded()
        #expect(collection.frame == stack.bounds)
    }
}
#endif
