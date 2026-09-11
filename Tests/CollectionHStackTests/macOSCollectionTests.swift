#if os(macOS)
import AppKit
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct MacOSCollectionHStackTests {
    @Test
    func measurementsAreCachedAndRedrawRemeasures() {
        let proxy = CollectionHStackProxy()
        let model = SizeModel()
        let configuration = CollectionHStack(count: 10000, columns: 2) { _ in
            Color.blue.frame(height: model.height)
        }.insets(horizontal: 0).itemSpacing(10).proxy(proxy)

        let view = NSCollectionHStack(configuration: configuration)
        #expect(view.fittingSize(forWidth: 210).height == 50)
        // Cached proportions survive content changes until explicitly redrawn.
        model.height = 75
        #expect(view.fittingSize(forWidth: 410).height == 100)
        #expect(view.fittingSize(forWidth: 310).height == 75)
        proxy.redraw()
        #expect(view.fittingSize(forWidth: 210).height == 75)
        view.disconnect()
    }

    @Test
    func nativeCollectionStaysVirtualizedAcrossResizeAndDistantScroll() async throws {
        _ = NSApplication.shared
        let configuration = CollectionHStack(count: 10000, columns: 3, rows: 2) { _ in
            Color.blue.aspectRatio(2 / 3, contentMode: .fit)
        }.insets(horizontal: 20, vertical: 5).itemSpacing(10)
            .scrollBehavior(.continuousLeadingEdge)
        let view = NSCollectionHStack(configuration: configuration)
        let window = makeWindow(view)
        defer { view.disconnect()
            window.close()
        }
        for width: CGFloat in [320, 768, 1366, 414, 1024] {
            let height = view.fittingSize(forWidth: width).height
            window.setContentSize(CGSize(width: width, height: height))
            view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            view.layoutSubtreeIfNeeded()
            #expect(view.collectionView.numberOfItems(inSection: 0) == 10000)
            let attributes = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let expected = (width - 60) / 3
            #expect(abs(attributes.size.width - expected) < 0.01)
            #expect(abs(attributes.size.height - expected * 1.5) < 0.1)
            #expect(!view.collectionView.visibleItems().isEmpty)
            #expect(view.collectionView.visibleItems().count < 30)
        }
        view.scrollTo(index: 9000, animated: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(view.scrollView.contentView.bounds.minX > 100_000)
        #expect(view.collectionView.indexPathsForVisibleItems().contains { $0.item >= 9000 })
        #expect(view.collectionView.visibleItems().count < 30)
    }

    @Test
    func representableNegotiatesHeightInSwiftUI() async throws {
        _ = NSApplication.shared
        let host = NSHostingController(rootView: VStack(spacing: 0) {
            CollectionHStack(count: 10000, columns: 2) { _ in
                Color.blue.aspectRatio(2, contentMode: .fit)
            }.insets(horizontal: 0).itemSpacing(10)
            Spacer(minLength: 0)
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.setContentSize(CGSize(width: 410, height: 500))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutSubtreeIfNeeded()
        let collection = try #require(findCollection(host.view))
        #expect(try abs(#require(collection.enclosingScrollView?.bounds.height) - 100) < 1)
        #expect(collection.numberOfItems(inSection: 0) == 10000)
    }

    @Test
    func collidingIDsSlicesAndMixedUpdatesKeepIdentity() {
        let data = (0 ..< 10).map(CollidingID.init)
        func configuration(_ values: ArraySlice<CollidingID>) -> CollectionHStack<CollidingID, ArraySlice<CollidingID>, CollidingID, Text> {
            CollectionHStack(uniqueElements: values, id: \.self, columns: 2) { Text("\($0.value)") }
        }
        let view = NSCollectionHStack(configuration: configuration(data[3 ..< 7]))
        #expect(view.index(id: CollidingID(value: 3)) == 0)
        #expect(view.index(id: CollidingID(value: 6)) == 3)
        let next = [CollidingID(value: 6), CollidingID(value: 4), CollidingID(value: 9)]
        view.update(configuration: configuration(next[...]), isScrollEnabled: true, dynamicTypeSize: .large)
        #expect(view.index(id: CollidingID(value: 6)) == 0)
        #expect(view.index(id: CollidingID(value: 3)) == nil)
        #expect(view.collectionView.numberOfItems(inSection: 0) == 3)
        view.update(configuration: configuration([]), isScrollEnabled: true, dynamicTypeSize: .large)
        view.scrollTo(index: -1, animated: false)
        view.scrollTo(index: 99, animated: false)
        #expect(view.collectionView.numberOfItems(inSection: 0) == 0)
        view.disconnect()
    }

    @Test
    func layoutVariantsPreserveColumnMajorOrdering() throws {
        let layouts: [CollectionHStackLayout] = [
            .grid(columns: 2.5, rows: 2, columnTrailingInset: 0),
            .minimumWidth(columnWidth: 80, rows: 2),
            .selfSizingSameSize(rows: 2), .selfSizingVariadicWidth(rows: 2),
        ]
        for layout in layouts {
            let view = NSCollectionHStack(configuration: CollectionHStack(uniqueElements: [0, 1, 2, 3], layout: layout) {
                Color.blue.frame(width: CGFloat(80 + $0 * 10), height: 40)
            }.insets(horizontal: 10, vertical: 5).itemSpacing(10))
            view.frame = CGRect(x: 0, y: 0, width: 300, height: view.fittingSize(forWidth: 300).height)
            view.layoutSubtreeIfNeeded()
            let first = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let second = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
            let third = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 2, section: 0)))
            #expect(first.frame.minX == second.frame.minX)
            #expect(second.frame.minY > first.frame.minY)
            #expect(third.frame.minX > first.frame.minX)
            view.disconnect()
        }
    }

    @Test
    func proxyBindingPrefixCarouselAndCallbacks() async throws {
        _ = NSApplication.shared
        let proxy = CollectionHStackProxy()
        var aligned: Int?
        var leading = 0
        var trailing = 0
        var prefetched = 0
        let configuration = CollectionHStack(count: 20, columns: 2, rows: 2) { _ in Color.blue.frame(height: 40) }
            .insets(horizontal: 10).itemSpacing(10).scrollBehavior(.columnPaging).proxy(proxy)
            .alignedLeadingElement(id: Binding(get: { aligned }, set: { aligned = $0 }))
            .onReachedLeadingEdge { leading += 1 }
            .onReachedTrailingEdge { trailing += 1 }
            .onPrefetchingElements { prefetched += $0.count }
        let view = NSCollectionHStack(configuration: configuration)
        let window = makeWindow(view)
        defer { view.disconnect()
            window.close()
        }
        view.frame = CGRect(x: 0, y: 0, width: 300, height: view.fittingSize(forWidth: 300).height)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        #expect(aligned == 0)
        #expect(leading == 1)
        proxy.scrollTo(index: 8, animated: false)
        let deadline = ContinuousClock.now + .seconds(2)
        while aligned != 8 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(aligned == 8)
        #expect(view.collectionView.frame.width == view.collectionLayout.collectionViewContentSize.width)
        #expect(prefetched > 0)
        proxy.scrollTo(index: 19, animated: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(trailing == 1)
        view.update(configuration: configuration.dataPrefix(3).asCarousel(), isScrollEnabled: false, dynamicTypeSize: .large)
        #expect(view.collectionView.numberOfItems(inSection: 0) == 100)
        #expect(view.index(id: 3) == nil)
        #expect(!view.scrollView.allowsScrolling)
        view.update(configuration: configuration.dataPrefix(3), isScrollEnabled: true, dynamicTypeSize: .large)
        #expect(view.collectionView.numberOfItems(inSection: 0) == 3)
    }

    @Test
    func allScrollBehaviorsRespectTheirPagingContract() {
        for behavior: CollectionHStackScrollBehavior in [.continuous, .continuousLeadingEdge, .columnPaging, .fullPaging] {
            let view = NSCollectionHStack(configuration: CollectionHStack(count: 100, columns: 2) { _ in
                Color.blue.frame(height: 40)
            }.insets(horizontal: 10).itemSpacing(10).scrollBehavior(behavior))
            view.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
            view.layoutSubtreeIfNeeded()
            let result = view.settledOffset(proposed: 700, gestureStart: 0)
            switch behavior {
            case .continuous: #expect(result == 700)
            case .continuousLeadingEdge: #expect(result == 725)
            case .columnPaging: #expect(result == 145)
            case .fullPaging: #expect(result == 290)
            }
            view.disconnect()
        }
    }

    @Test
    func hostingViewsAreReused() {
        let item = HostingCollectionViewItem()
        item.configure(Text("First"), id: 1)
        let host = item.view.subviews.first
        item.prepareForReuse()
        item.configure(Text("Second"), id: 2)
        #expect(item.view.subviews.count == 1)
        #expect(item.view.subviews.first === host)
    }

    @Test
    func alignmentScrollsThroughIntermediateOffsets() async throws {
        for behavior: CollectionHStackScrollBehavior in [.continuousLeadingEdge, .columnPaging, .fullPaging] {
            _ = NSApplication.shared
            let view = NSCollectionHStack(configuration: CollectionHStack(count: 100, columns: 2) { _ in
                Color.blue.frame(height: 40)
            }.insets(horizontal: 10).itemSpacing(10).scrollBehavior(behavior))
            let window = makeWindow(view)
            defer {
                view.disconnect()
                window.close()
            }
            view.layoutSubtreeIfNeeded()
            let proposed: CGFloat = behavior == .fullPaging ? 200 : 100
            let target = view.settledOffset(proposed: proposed, gestureStart: 0)
            view.scrollView.willScroll?()
            view.scrollView.contentView.scroll(to: CGPoint(x: proposed, y: 0))
            view.scrollView.didScroll?()

            var sawIntermediateOffset = false
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
                let offset = view.scrollView.contentView.bounds.minX
                if offset > proposed + 1 && offset < target - 1 {
                    sawIntermediateOffset = true
                }
                if abs(offset - target) < 0.5 {
                    break
                }
            }
            #expect(sawIntermediateOffset, "Alignment must scroll to its target instead of jumping there")
            #expect(abs(view.scrollView.contentView.bounds.minX - target) < 0.5)
        }
    }

    @Test
    func activeGestureDefersAlignmentAndInterruptsAnimation() async throws {
        _ = NSApplication.shared
        let view = NSCollectionHStack(configuration: CollectionHStack(count: 100, columns: 2) { _ in
            Color.blue.frame(height: 40)
        }.insets(horizontal: 10).itemSpacing(10).scrollBehavior(.continuousLeadingEdge))
        let window = makeWindow(view)
        defer {
            view.disconnect()
            window.close()
        }
        view.layoutSubtreeIfNeeded()
        let scrollView = view.scrollView
        scrollView.isTrackingScroll = true
        scrollView.willScroll?()
        scrollView.contentView.scroll(to: CGPoint(x: 100, y: 0))
        scrollView.didScroll?()
        try await Task.sleep(for: .milliseconds(250))
        #expect(scrollView.contentView.bounds.minX == 100, "Holding a gesture still must not start alignment")

        scrollView.isTrackingScroll = false
        scrollView.didScroll?()
        let deadline = ContinuousClock.now + .seconds(2)
        while scrollView.contentView.bounds.minX <= 101 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(scrollView.contentView.bounds.minX > 101)
        #expect(scrollView.contentView.bounds.minX < 144)

        scrollView.isTrackingScroll = true
        scrollView.willScroll?()
        scrollView.contentView.scroll(to: CGPoint(x: 40, y: 0))
        scrollView.didScroll?()
        try await Task.sleep(for: .milliseconds(300))
        #expect(scrollView.contentView.bounds.minX == 40, "A new gesture must cancel the previous animation")

        scrollView.isTrackingScroll = false
        scrollView.didScroll?()
        try await Task.sleep(for: .milliseconds(500))
        #expect(abs(scrollView.contentView.bounds.minX) < 0.5)
    }

    @Test
    func visibleLayoutBenchmark() {
        var expectedAttributes: Int?
        for count in [100, 10000, 100_000] {
            let view = NSCollectionHStack(configuration: CollectionHStack(count: count, columns: 3) { _ in
                Color.blue.frame(height: 40)
            }.insets(horizontal: 10).itemSpacing(10))
            view.frame = CGRect(x: 0, y: 0, width: 500, height: 200)
            view.layoutSubtreeIfNeeded()
            var attributes = 0
            let elapsed = ContinuousClock().measure {
                for _ in 0 ..< 5000 {
                    attributes += view.collectionLayout.layoutAttributesForElements(in: CGRect(x: 0, y: 0, width: 500, height: 200)).count
                }
            }
            if let expectedAttributes {
                #expect(attributes == expectedAttributes)
            } else {
                expectedAttributes = attributes
            }
            #expect(attributes > 0 && attributes < 100_000)
            print("LAYOUT_BENCHMARK items=\(count) queries=5000 duration=\(elapsed)")
            view.disconnect()
        }
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        return window
    }

    private func findCollection(_ view: NSView) -> NSCollectionView? {
        if let view = view as? NSCollectionView {
            return view
        }
        return view.subviews.lazy.compactMap(findCollection).first
    }
}

private final class SizeModel { var height: CGFloat = 50 }
private struct CollidingID: Hashable {
    let value: Int
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

#endif
