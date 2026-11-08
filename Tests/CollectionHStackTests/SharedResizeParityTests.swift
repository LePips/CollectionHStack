@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct SharedResizeParityTests {
    #if os(iOS) || os(macOS)
    @Test
    func `adaptive and fractional resizes retain their horizontal anchor`() async throws {
        let fixture = LibraryFixture(itemCount: 10000)
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        let sweep = Array(stride(from: CGFloat(1180), through: 390, by: -10))
        let report = fixture.recordLiveResize(widths: sweep + sweep.reversed())
        #expect(report.maximumAnchorDrift < 1)
        #expect(fixture.visibleCellCount > 0 && fixture.visibleCellCount < 30)
        #expect(report.suppliedViews < report.frames * fixture.visibleCellCount)
        fixture.scroll(toItem: 180)
        let boundaries: [CGFloat] = [609.75, 610, 610.25, 659.75, 660, 660.25, 819.75, 820, 820.25]
        #expect(fixture.recordLiveResize(widths: (0 ..< 12).flatMap { _ in boundaries }).maximumAnchorDrift < 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.visibleContentIsCurrent())
    }

    @Test
    func `vertical insets reuse measurements and deliver current content`() async throws {
        let fixture = LibraryFixture(itemCount: 10000)
        fixture.layOut(width: 1180)
        fixture.scroll(toItem: 60)
        try await Task.sleep(for: .milliseconds(200))
        let measurements = fixture.state.representativeViews
        let report = fixture.recordFrames(values: [10, 20, 40, 15, 0]) { fixture.state.topInset = $0 }
        #expect(fixture.state.representativeViews == measurements)
        #expect(report.maximumAnchorDrift < 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(fixture.visibleContentIsCurrent())
    }
    #endif

    @Test
    func `retained lookup follows slices with unchanged identities`() {
        struct Element { let id: Int }
        let first = [Element(id: -1), Element(id: 10), Element(id: 20)][1...]
        let second = [Element(id: -2), Element(id: -1), Element(id: 10), Element(id: 20)][2...]
        var index = CollectionDataIndex<Int>()
        var lookup: [Int: Int] = [:]
        #expect(index.update(from: first, identifier: { $0.id }, prefix: nil, retainingLookup: &lookup))
        #expect(!index.update(from: second, identifier: { $0.id }, prefix: nil, retainingLookup: &lookup))
        #expect(lookup == [10: 2, 20: 3])
        // Horizontal carousels repeat the source without copying its elements.
        #expect(index.element(in: second, at: 5).id == 20)
    }

    @Test
    func `deferred updates deliver only the latest action and support cancellation`() async throws {
        let update = CollectionDeferredUpdate()
        var values: [Int] = []
        for value in 0 ..< 100 {
            update.schedule(after: 0.02) { values.append(value) }
        }
        try await Task.sleep(for: .milliseconds(80))
        #expect(values == [99])
        update.schedule(after: 0.02) { values.append(100) }
        update.cancel()
        try await Task.sleep(for: .milliseconds(80))
        #expect(values == [99])
        update.schedule(after: 0) { values.append(101) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(values == [99, 101])
    }

    @Test
    func `hosted state survives resizing and resets when the item changes`() async throws {
        var seen: [Int] = []
        #if os(macOS)
        _ = NSApplication.shared
        let item = HostingCollectionViewItem<StatefulCard>()
        let native = item.view
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = parent
        parent.addSubview(native)
        window.orderBack(nil)
        defer { window.close() }
        func configure(seed: Int, id: Int) {
            item.configure(StatefulCard(seed: seed) { seen.append($0) }, id: AnyHashable(id))
        }
        func layout() {
            native.layoutSubtreeIfNeeded()
        }
        #else
        let item = HostingCollectionViewCell<StatefulCard>()
        let native = item
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(native)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func configure(seed: Int, id: Int) {
            item.setup(view: StatefulCard(seed: seed) { seen.append($0) }, id: AnyHashable(id))
        }
        func layout() {
            native.layoutIfNeeded()
        }
        #endif
        native.frame = CGRect(x: 0, y: 0, width: 180, height: 120)
        configure(seed: 1, id: 10)
        layout()
        try await Task.sleep(for: .milliseconds(60))
        #expect(seen.last == 1)
        configure(seed: 99, id: 10)
        for width: CGFloat in [310.5, 220, 250] {
            native.frame.size.width = width
            layout()
            try await Task.sleep(for: .milliseconds(60))
            #expect(seen.last == 1)
        }
        item.prepareForReuse()
        configure(seed: 2, id: 20)
        layout()
        try await Task.sleep(for: .milliseconds(60))
        #expect(seen.last == 2)
    }
}

private struct StatefulCard: View {
    @State
    private var value: Int
    let report: (Int) -> Void
    init(seed: Int, report: @escaping (Int) -> Void) {
        _value = State(initialValue: seed)
        self.report = report
    }

    var body: some View {
        report(value)
        return Color.blue.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
