@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct InitialElementTests {
    private typealias Configuration = CollectionHStack<Int, [Int], Int, ColorContent>
    #if canImport(UIKit)
    private typealias NativeView = UICollectionHStack<Int, [Int], Int, ColorContent>
    #else
    private typealias NativeView = NSCollectionHStack<Int, [Int], Int, ColorContent>
    #endif

    @Test(arguments: 0 ..< 4)
    func firstLayoutPositionsTargetImmediately(behaviorIndex: Int) async throws {
        let behavior: CollectionHStackScrollBehavior = [.continuous, .continuousLeadingEdge, .columnPaging, .fullPaging][behaviorIndex]
        let configuration = configuration().scrollBehavior(behavior).initialElement(id: 107)
        let view = makeView(configuration)
        let close = present(view)
        defer { close() }

        let frame = try itemFrame(view, index: 7)
        let expected: CGFloat = switch behavior {
        case .continuousLeadingEdge, .columnPaging: frame.minX - 20
        case .continuous, .fullPaging: frame.midX - viewportWidth(view) / 2
        }
        #expect(abs(offset(view) - expected) < 0.5)
        // A queued sizing/layout pass must not reset the initial position.
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(offset(view) - expected) < 0.5)
    }

    @Test(arguments: 0 ..< 4, [false, true])
    func waitsForNonEmptyData(behaviorIndex: Int, populateBeforeFirstLayout: Bool) async throws {
        let behavior: CollectionHStackScrollBehavior = [.continuous, .continuousLeadingEdge, .columnPaging, .fullPaging][behaviorIndex]
        let view = makeView(configuration(data: []).scrollBehavior(behavior).initialElement(id: 107))
        // Empty updates must not consume the request, including one with no target.
        update(view, configuration(data: []).scrollBehavior(behavior).initialElement(id: nil))
        var close: (() -> Void)?
        defer { close?() }
        if !populateBeforeFirstLayout {
            close = present(view)
            update(view, configuration(data: []).scrollBehavior(behavior).initialElement(id: 107))
            layout(view, width: 320)
        }

        update(view, configuration().scrollBehavior(behavior).initialElement(id: 115))
        if populateBeforeFirstLayout {
            close = present(view)
        } else {
            layout(view, width: 320)
        }

        let frame = try itemFrame(view, index: 15)
        let expected: CGFloat = switch behavior {
        case .continuousLeadingEdge, .columnPaging: frame.minX - 20
        case .continuous, .fullPaging: frame.midX - viewportWidth(view) / 2
        }
        #expect(abs(offset(view) - expected) < 0.5)
        try await Task.sleep(for: .milliseconds(200))
        #expect(abs(offset(view) - expected) < 0.5)
    }

    @Test(arguments: [false, true], [false, true])
    func missingTargetIsNotRetriedWithoutIDChange(usePrefix: Bool, startsEmpty: Bool) {
        let initial = usePrefix
            ? configuration().initialElement(id: 107).dataPrefix(3)
            : configuration(data: Array(100 ... 105)).initialElement(id: 107)
        let view = makeView(startsEmpty ? configuration(data: []).initialElement(id: 107) : initial)
        if startsEmpty {
            update(view, initial)
        }
        // Data or prefix changes alone do not retry a missing target.
        update(view, configuration().initialElement(id: 107))
        let close = present(view)
        defer { close() }
        #expect(abs(offset(view)) < 0.5)
    }

    @Test
    func unchangedIDDoesNotReapplyAfterUpdatesRedrawResizeOrRefill() {
        let initial = configuration().initialElement(id: 107)
        let view = makeView(initial)
        let close = present(view)
        defer { close() }
        view.scrollTo(index: 0, animated: false)
        update(view, configuration().initialElement(id: 107).itemSpacing(12))
        view.snapshotReload()
        layout(view, width: 360)
        #expect(abs(offset(view)) < 0.5)
        update(view, configuration(data: Array(100 ... 125)).initialElement(id: 107))
        layout(view, width: 360)
        #expect(abs(offset(view)) < 0.5)
        update(view, configuration(data: []).initialElement(id: 107))
        layout(view, width: 360)
        update(view, configuration().initialElement(id: 107))
        layout(view, width: 360)
        #expect(abs(offset(view)) < 0.5)
    }

    @Test(arguments: 0 ..< 4)
    func nonNilIDTransitionsReposition(behaviorIndex: Int) async throws {
        let behavior: CollectionHStackScrollBehavior = [.continuous, .continuousLeadingEdge, .columnPaging, .fullPaging][behaviorIndex]
        let view = makeView(configuration().scrollBehavior(behavior).initialElement(id: nil))
        let close = present(view)
        defer { close() }

        // Covers nil -> ID, ID -> different ID, and returning to an earlier ID.
        for id in [107, 115, 107] {
            update(view, configuration().scrollBehavior(behavior).initialElement(id: id))
            // An ID-only update must schedule layout without resizing the view.
            #if canImport(UIKit)
            view.layoutIfNeeded()
            #else
            view.layoutSubtreeIfNeeded()
            #endif
            let frame = try itemFrame(view, index: id - 100)
            let expected: CGFloat = switch behavior {
            case .continuousLeadingEdge, .columnPaging: frame.minX - 20
            case .continuous, .fullPaging: frame.midX - viewportWidth(view) / 2
            }
            #expect(abs(offset(view) - expected) < 0.5)
            try await Task.sleep(for: .milliseconds(200))
            #expect(abs(offset(view) - expected) < 0.5)
        }
    }

    @Test
    func nilThenSameIDTriggersAnotherEvaluation() throws {
        let view = makeView(configuration().initialElement(id: 107))
        let close = present(view)
        defer { close() }
        view.scrollTo(index: 0, animated: false)

        update(view, configuration().initialElement(id: nil))
        layout(view, width: 320)
        #expect(abs(offset(view)) < 0.5)
        update(view, configuration().initialElement(id: 107))
        layout(view, width: 320)
        #expect(try abs(offset(view) - (itemFrame(view, index: 7).minX - 20)) < 0.5)
    }

    @Test
    func changedIDWaitsForNonEmptyData() throws {
        let view = makeView(configuration().initialElement(id: 107))
        let close = present(view)
        defer { close() }

        update(view, configuration(data: []).initialElement(id: 115))
        layout(view, width: 320)
        update(view, configuration(data: []).initialElement(id: 115))
        layout(view, width: 320)
        update(view, configuration().initialElement(id: 115))
        layout(view, width: 320)
        #expect(try abs(offset(view) - (itemFrame(view, index: 15).minX - 20)) < 0.5)
    }

    @Test
    func changedIDUsesUpdatedData() throws {
        let view = makeView(configuration().initialElement(id: 107))
        let close = present(view)
        defer { close() }

        update(view, configuration(data: Array(100 ... 140)).initialElement(id: 125))
        layout(view, width: 320)
        #expect(try abs(offset(view) - (itemFrame(view, index: 25).minX - 20)) < 0.5)
    }

    @Test(arguments: [nil, 115, 999] as [Int?])
    func changedIDReplacesPendingTarget(id: Int?) throws {
        let view = makeView(configuration().initialElement(id: 107))
        update(view, configuration().initialElement(id: id))
        let close = present(view)
        defer { close() }

        let expected = try id == 115 ? itemFrame(view, index: 15).minX - 20 : 0
        #expect(abs(offset(view) - expected) < 0.5)
    }

    @Test
    func pendingTargetUsesIdentityAfterReordering() throws {
        let view = makeView(configuration().initialElement(id: 107))
        update(view, configuration(data: [100, 101, 102, 103, 107] + Array(108 ... 120)).initialElement(id: 107))
        let close = present(view)
        defer { close() }
        #expect(try abs(offset(view) - (itemFrame(view, index: 4).minX - 20)) < 0.5)
    }

    @Test
    func removedPendingTargetDoesNotScrollToItsOldIndex() {
        let view = makeView(configuration().initialElement(id: 107))
        update(view, configuration(data: Array(110 ... 130)).initialElement(id: 107))
        let close = present(view)
        defer { close() }
        #expect(abs(offset(view)) < 0.5)
    }

    @Test(arguments: [100, 120])
    func targetsAtContentEdgesAreClamped(id: Int) {
        let view = makeView(configuration().scrollBehavior(.continuous).initialElement(id: id))
        let close = present(view)
        defer { close() }
        #if canImport(UIKit)
        let collection = collection(view)
        let maximum = max(0, collection.contentSize.width - collection.bounds.width)
        #else
        let maximum = max(0, view.collectionLayout.collectionViewContentSize.width - viewportWidth(view))
        #endif
        #expect(abs(offset(view) - (id == 100 ? 0 : maximum)) < 0.5)
    }

    #if canImport(UIKit)
    @Test
    func fullPagingContinuesFromInitialPage() throws {
        let view = makeView(configuration().scrollBehavior(.fullPaging).initialElement(id: 115))
        let close = present(view)
        defer { close() }
        let collection = collection(view)
        let layout = try #require(collection.collectionViewLayout as? FullPagingFlowLayout)
        let start = offset(view)
        let target = layout.targetContentOffset(
            forProposedContentOffset: CGPoint(x: start + 50, y: 0),
            withScrollingVelocity: CGPoint(x: 1, y: 0)
        )
        #expect(target.x > start)
        #expect(target.x - start <= 290 * 1.5)
    }
    #endif

    private func configuration(data: [Int] = Array(100 ... 120)) -> Configuration {
        CollectionHStack(uniqueElements: data, id: \.self, columns: 2, rows: 2) { _ in ColorContent() }
            .insets(horizontal: 20).itemSpacing(10).scrollBehavior(.continuousLeadingEdge)
    }

    private func makeView(_ configuration: Configuration) -> NativeView {
        #if canImport(UIKit)
        NativeView(
            id: configuration.id, alignedLeadingElementID: nil, clipsToBounds: true,
            data: configuration.data, dataPrefix: configuration.dataPrefix, didScrollToItems: { _ in },
            insets: configuration.insets, isCarousel: configuration.isCarousel, itemSpacing: configuration.itemSpacing,
            layout: configuration.layout, onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .offset(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .offset(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: configuration.proxy, scrollBehavior: configuration.scrollBehavior,
            initialElementID: configuration.initialElementID, viewProvider: configuration.viewProvider
        )
        #else
        NativeView(configuration: configuration)
        #endif
    }

    private func update(_ view: NativeView, _ configuration: Configuration) {
        #if canImport(UIKit)
        view.configure(configuration)
        view.update(
            newData: configuration.data,
            alignedLeadingElementID: nil,
            dataPrefix: configuration.dataPrefix,
            layout: configuration.layout,
            insets: configuration.insets,
            itemSpacing: configuration.itemSpacing
        )
        #else
        view.update(configuration: configuration, isScrollEnabled: true, dynamicTypeSize: .large)
        #endif
    }

    private func present(_ view: NativeView) -> () -> Void {
        #if canImport(UIKit)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        // These assertions use collection coordinates. tvOS otherwise adds its
        // overscan safe-area inset after the test window becomes visible.
        collection(view).contentInsetAdjustmentBehavior = .never
        layout(view, width: 320)
        window.makeKeyAndVisible()
        view.layoutIfNeeded()
        return { window.isHidden = true }
        #else
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 90),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        layout(view, width: 320)
        window.orderBack(nil)
        return { view.disconnect()
            window.close()
        }
        #endif
    }

    private func layout(_ view: NativeView, width: CGFloat) {
        view.frame = CGRect(x: 0, y: 0, width: width, height: view.fittingSize(forWidth: width).height)
        #if canImport(UIKit)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #else
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        #endif
    }

    private func offset(_ view: NativeView) -> CGFloat {
        #if canImport(UIKit)
        collection(view).contentOffset.x
        #else
        view.scrollView.contentView.bounds.minX
        #endif
    }

    private func viewportWidth(_ view: NativeView) -> CGFloat {
        #if canImport(UIKit)
        collection(view).bounds.width
        #else
        view.scrollView.contentSize.width
        #endif
    }

    private func itemFrame(_ view: NativeView, index: Int) throws -> CGRect {
        #if canImport(UIKit)
        let attributes = collection(view).collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        #else
        let attributes = view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        #endif
        return try #require(attributes).frame
    }

    #if canImport(UIKit)
    private func collection(_ view: NativeView) -> UICollectionView {
        view.subviews.compactMap { $0 as? UICollectionView }.first!
    }
    #endif
}

private struct ColorContent: View {
    var body: some View {
        Color.blue.frame(height: 40)
    }
}
