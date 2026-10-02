@testable import CollectionHStack
import QuartzCore
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct ResizeAnimationTests {
    @Test(arguments: [CGFloat(0), CGFloat(0.5)])
    func transitionPreservesStartingFrameAndFinalModel(anchor: CGFloat) throws {
        let container = CALayer()
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: anchor, y: anchor)
        container.addSublayer(layer)
        layer.frame = CGRect(x: 20, y: 10, width: 200, height: 100)
        let item = ResizeAnimation.Item(id: 1, layer: layer)
        let resize = ResizeAnimation(items: [item], in: container, enabled: true)
        layer.frame = CGRect(x: 50, y: 30, width: 100, height: 50)
        resize.apply(to: [item], in: container)
        let animation = try #require(layer.animation(forKey: ResizeAnimation.key) as? CABasicAnimation)
        let transform = try #require(animation.fromValue as? NSValue).caTransform3DValue
        #expect(transform.m11 == 2)
        #expect(transform.m22 == 2)
        #expect(transform.m41 == -30 + 100 * anchor)
        #expect(transform.m42 == -20 + 50 * anchor)
        #expect(animation.isAdditive)
        #expect(layer.frame == CGRect(x: 50, y: 30, width: 100, height: 50))
        #expect(CATransform3DIsIdentity(layer.transform))

        _ = ResizeAnimation(items: [item], in: container, enabled: false)
        #expect(layer.animation(forKey: ResizeAnimation.key) == nil)
    }

    @Test
    func reusedLayersDoNotAnimatePreviousIdentity() {
        let container = CALayer()
        let layer = CALayer()
        container.addSublayer(layer)
        layer.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let resize = ResizeAnimation(items: [.init(id: 1, layer: layer)], in: container, enabled: true)
        layer.frame.size = CGSize(width: 100, height: 50)
        resize.apply(to: [.init(id: 2, layer: layer)], in: container)
        #expect(layer.animation(forKey: ResizeAnimation.key) == nil)
    }

    @Test(arguments: [CGFloat(0), CGFloat(0.5), CGFloat(0.25)])
    func breakpointAnimatesIntermediateFramesAndRetargets(fraction: CGFloat) async throws {
        let breakpoint: CGFloat = fraction == 0 ? 320 : (fraction == 0.5 ? 270 : 245)
        let originalWidth = (breakpoint - 11) / 2
        let fixture = ResizeFixture(count: 10000, animated: true, fraction: fraction)
        defer { fixture.close() }
        fixture.resize(breakpoint - 1)
        try await Task.sleep(for: .milliseconds(300))
        let layer = try #require(fixture.firstLayer)
        #expect(layer.animation(forKey: ResizeAnimation.key) == nil, "Initial layout must not animate")
        fixture.resize(breakpoint)
        let targetWidth = layer.bounds.width
        #expect(abs(targetWidth - 100) < 0.1)
        if fixture.reduceMotion {
            return
        }
        #expect(layer.animation(forKey: ResizeAnimation.key) != nil)
        try await Task.sleep(for: .milliseconds(45))
        let intermediate = try #require(layer.presentation()).frame.width
        #expect(intermediate > targetWidth + 0.1)
        #expect(intermediate < originalWidth)

        fixture.resize(breakpoint - 1)
        let retarget = try #require(layer.animation(forKey: ResizeAnimation.key) as? CABasicAnimation)
        let from = try #require(retarget.fromValue as? NSValue).caTransform3DValue
        #expect(abs(from.m11 * layer.bounds.width - intermediate) < 3, "Retarget from the displayed size")
        #expect(layer.animationKeys()?.filter { $0 == ResizeAnimation.key }.count == 1)
        try await Task.sleep(for: .milliseconds(300))
        // Core Animation can retain a completed key until its next transaction;
        // the rendered frame must already have reached the final model geometry.
        #expect(try abs(#require(layer.presentation()).frame.width - originalWidth) < 0.5)
        #expect(fixture.visibleCount < 30)
    }

    @Test
    func changingSizingConfigurationAnimatesWithoutChangingContainerWidth() async throws {
        let fixture = ResizeFixture(count: 10000, animated: true)
        defer { fixture.close() }
        fixture.resize(320)
        try await Task.sleep(for: .milliseconds(100))
        fixture.setMinimumWidth(150)
        fixture.resize(320)
        let layer = try #require(fixture.firstLayer)
        #expect(abs(layer.bounds.width - 155) < 0.1)
        if !fixture.reduceMotion {
            #expect(layer.animation(forKey: ResizeAnimation.key) != nil)
            try await Task.sleep(for: .milliseconds(45))
            let width = try #require(layer.presentation()).frame.width
            #expect(width > 100 && width < 155)
        }
    }

    @Test
    func sustainedResizingSettlesAtLatestSize() async throws {
        let fixture = ResizeFixture(count: 10000, animated: true, fraction: 0.5)
        defer { fixture.close() }
        fixture.resize(320)
        for step in 0 ..< 90 {
            fixture.resize(CGFloat(300 + (step % 30) * 8))
            try await Task.sleep(for: .milliseconds(16))
        }
        fixture.resize(320)
        try await Task.sleep(for: .milliseconds(300))
        let layer = try #require(fixture.firstLayer)
        #expect(try abs(#require(layer.presentation()).frame.width - 100) < 0.5)
        #expect(fixture.visibleCount < 30)
        #expect(fixture.configurations < 100)
    }

    @Test
    func optingOutAndReuseClearActiveAnimation() async throws {
        let fixture = ResizeFixture(count: 10000, animated: true)
        defer { fixture.close() }
        fixture.resize(319)
        try await Task.sleep(for: .milliseconds(100))
        fixture.resize(320)
        fixture.setAnimated(false)
        #expect(fixture.firstLayer?.animation(forKey: ResizeAnimation.key) == nil)
        fixture.resize(319)
        #expect(fixture.firstLayer?.animation(forKey: ResizeAnimation.key) == nil)

        #if os(macOS)
        let item = HostingCollectionViewItem()
        item.configure(Color.blue, id: 1)
        item.view.layer?.add(CABasicAnimation(keyPath: "opacity"), forKey: ResizeAnimation.key)
        item.prepareForReuse()
        #expect(item.view.layer?.animation(forKey: ResizeAnimation.key) == nil)
        #else
        let cell = HostingCollectionViewCell<Color>()
        cell.setup(view: .blue, id: 1)
        cell.layer.add(CABasicAnimation(keyPath: "opacity"), forKey: ResizeAnimation.key)
        cell.prepareForReuse()
        #expect(cell.layer.animation(forKey: ResizeAnimation.key) == nil)
        #endif
    }

    @Test
    func repeatedResizePerformanceStaysBoundedByVisibleItems() async throws {
        for count in [100, 10000] {
            for animated in [false, true] {
                let fixture = ResizeFixture(count: count, animated: animated)
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
                let median = samples[samples.count / 2]
                let p95 = samples[Int(Double(samples.count) * 0.95)]
                print(
                    "RESIZE_PERF count=\(count) animated=\(animated) median_ms=\(median) p95_ms=\(p95) configurations=\(fixture.configurations - configuredBefore)"
                )
                #expect(p95 < 16.67, "Main-thread resize work must fit a 60 Hz frame budget")
                #expect(fixture.configurations - configuredBefore < 1000, "Resizing must not recreate the full collection")
            }
        }
    }
}

@MainActor
private final class ResizeFixture {
    private final class Counter { var value = 0 }
    private let counter = Counter()
    private var configuration: CollectionHStack<Int, Range<Int>, Int, AnyView>
    var configurations: Int {
        counter.value
    }

    #if os(macOS)
    private let stack: NSCollectionHStack<Int, Range<Int>, Int, AnyView>
    private let window: NSWindow
    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

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

    var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var visibleCount: Int {
        collection.visibleCells.count
    }

    var firstLayer: CALayer? {
        collection.cellForItem(at: IndexPath(item: 0, section: 0))?.layer
    }
    #endif

    init(count: Int, animated: Bool, fraction: CGFloat = 0) {
        let counter = counter
        configuration = CollectionHStack(
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
        .copy(modifying: \.animatesResizing, to: animated)
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
            dataPrefix: nil, didScrollToItems: { _ in }, insets: .init(), isCarousel: false,
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

    func setAnimated(_ enabled: Bool) {
        configuration = configuration.copy(modifying: \.animatesResizing, to: enabled)
        #if os(macOS)
        stack.update(configuration: configuration, isScrollEnabled: true, dynamicTypeSize: .large)
        #else
        stack.configure(configuration)
        #endif
    }

    func setMinimumWidth(_ width: CGFloat) {
        configuration = CollectionHStack(
            uniqueElements: configuration.data,
            id: \.self,
            minWidth: width,
            content: configuration.viewProvider
        )
        .insets(horizontal: 0)
        .itemSpacing(10)
        .copy(modifying: \.animatesResizing, to: configuration.animatesResizing)
        #if os(macOS)
        stack.update(configuration: configuration, isScrollEnabled: true, dynamicTypeSize: .large)
        #else
        stack.configure(configuration)
        stack.update(newData: configuration.data, alignedLeadingElementID: nil, layout: configuration.layout)
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
