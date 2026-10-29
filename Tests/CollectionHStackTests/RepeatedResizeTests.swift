@testable import CollectionHStack
import QuartzCore
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct RepeatedResizeTests {
    @Test
    func `sustained resizing settles at latest size`() async throws {
        let fixture = ResizeFixture(count: 10000, fraction: 0.5)
        defer { fixture.close() }
        fixture.resize(320)
        for step in 0 ..< 90 {
            fixture.resize(CGFloat(300 + (step % 30) * 8))
            try await Task.sleep(for: .milliseconds(16))
        }
        fixture.resize(320)
        try await Task.sleep(for: .milliseconds(300))
        let layer = try #require(fixture.firstLayer)
        #expect(abs(layer.frame.width - 100) < 0.5)
        #expect(fixture.visibleCount < 30)
        #expect(fixture.configurations < 100)
    }

    @Test
    func `repeated resize performance stays bounded by visible items`() async throws {
        for count in [100, 10000] {
            let fixture = ResizeFixture(count: count)
            defer { fixture.close() }
            fixture.resize(320)
            try await Task.sleep(for: .milliseconds(50))
            var samples: [Double] = []
            let configuredBefore = fixture.configurations
            for step in 0 ..< 240 {
                let start = CACurrentMediaTime()
                fixture.resize(CGFloat(300 + (step % 60) * 8))
                samples.append((CACurrentMediaTime() - start) * 1000)
                #expect(fixture.visibleCount > 0 && fixture.visibleCount < 30)
            }
            samples.sort()
            let p95 = samples[Int(Double(samples.count) * 0.95)]
            #expect(p95 < 16.67, "Main-thread resize work must fit a 60 Hz frame budget")
            #expect(fixture.configurations - configuredBefore < 1000, "Resizing must not recreate the full collection")
        }
    }
}

@MainActor
private final class ResizeFixture {
    private final class Counter { var value = 0 }
    private let counter = Counter()
    var configurations: Int {
        counter.value
    }

    #if os(macOS)
    private let stack: NSCollectionHStack<Int, Range<Int>, Int, AnyView>
    private let window: NSWindow

    var visibleCount: Int {
        stack.collectionView.visibleItems().count
    }

    var firstLayer: CALayer? {
        stack.collectionView.item(at: IndexPath(item: 0, section: 0))?.view.layer
    }
    #else
    private let stack: UICollectionHStack<Int, Range<Int>, Int, AnyView>
    private let window: UIWindow
    private var collection: UICollectionView {
        stack.subviews.compactMap { $0 as? UICollectionView }.first!
    }

    var visibleCount: Int {
        collection.visibleCells.count
    }

    var firstLayer: CALayer? {
        collection.cellForItem(at: IndexPath(item: 0, section: 0))?.layer
    }
    #endif

    init(count: Int, fraction: CGFloat = 0) {
        let counter = counter
        let configuration = CollectionHStack(
            uniqueElements: 0 ..< count,
            id: \.self,
            minWidth: 100,
            columnFraction: fraction
        ) { _ in
            counter.value += 1
            return AnyView(Color.blue.aspectRatio(2, contentMode: .fit))
        }
        .insets(horizontal: 0)
        .itemSpacing(10)
        #if os(macOS)
        _ = NSApplication.shared
        stack = NSCollectionHStack(configuration: configuration)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 500))
        window.contentView = parent
        parent.addSubview(stack)
        window.orderFront(nil)
        #else
        stack = UICollectionHStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: false, data: 0 ..< count,
            dataPrefix: nil, insets: .init(), isCarousel: false,
            itemSpacing: 10, layout: configuration.layout,
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: .continuous, viewProvider: configuration.viewProvider
        )
        stack.configure(configuration)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 500))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(stack)
        window.makeKeyAndVisible()
        collection.contentInsetAdjustmentBehavior = .never
        #endif
    }

    func resize(_ width: CGFloat) {
        stack.frame = CGRect(origin: .zero, size: stack.fittingSize(forWidth: width))
        #if os(macOS)
        stack.needsLayout = true
        stack.layoutSubtreeIfNeeded()
        #else
        stack.setNeedsLayout()
        stack.layoutIfNeeded()
        #endif
    }

    func close() {
        #if os(macOS)
        stack.disconnect()
        window.close()
        #else
        window.isHidden = true
        #endif
    }
}
