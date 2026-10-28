#if os(iOS)
@testable import CollectionHStack
import SwiftUI
import Testing

/// Replays the resize patterns of an adaptive app: a container publishes its width
/// through the environment, so every row re-evaluates on each resize frame, and
/// each row uses fractional minimum-width columns with unclipped content.
@Suite(.serialized)
@MainActor
struct AdaptiveResizeTests {

    @Test
    func `live window resizing keeps rows consistent every frame`() {
        let fixture = AdaptiveRowsFixture()
        fixture.layOut(width: 1180)
        fixture.scrollSecondRow(toItem: 10)

        let widths = Array(stride(from: CGFloat(1180), through: 700, by: -6)) + Array(stride(from: CGFloat(700), through: 1180, by: 6))
        let report = fixture.recordLiveResize(widths: widths)

        #expect(report.maximumHeightMismatch < 1, "Rows and their cells must agree on height every frame")
        #expect(report.maximumAnchorDrift < 1, "A scrolled row keeps its leading item aligned")
    }

    /// System sidebars on iPadOS propose the destination width once and snap the
    /// content to it, so each row's whole resize lands in a single frame.
    @Test
    func `sidebar snaps resize every row within one frame`() async throws {
        let fixture = AdaptiveRowsFixture()
        fixture.layOut(width: 1180)
        fixture.scrollSecondRow(toItem: 10)
        try await Task.sleep(for: .milliseconds(300))

        let report = try await fixture.recordSnaps(widths: [860, 1180, 860, 1180, 860, 1180, 860, 1180])

        #expect(report.maximumHeightMismatch < 1, "Rows and their cells must agree on height every frame")
        #expect(report.maximumAnchorDrift < 1, "A scrolled row keeps its leading item aligned")
    }

    /// A home screen of many rows in a non-lazy stack, most of them outside the window.
    @Test
    func `rows outside the window are correct once scrolled into view`() async throws {
        let fixture = AdaptiveRowsFixture(rowCount: 14, height: 1000)
        fixture.layOut(width: 1180)
        fixture.scrollSecondRow(toItem: 10)
        try await Task.sleep(for: .milliseconds(300))

        let widths = Array(stride(from: CGFloat(1180), through: 700, by: -6)) + Array(stride(from: CGFloat(700), through: 1180, by: 6))
        _ = fixture.recordLiveResize(widths: widths)
        try await Task.sleep(for: .milliseconds(300))
        let report = try await fixture.recordSnaps(widths: [860, 1180, 860, 1180, 860, 1180, 860, 1180])
        #expect(report.maximumAnchorDrift < 1)

        // Every row is correct once scrolled into view, including the last.
        fixture.layOut(width: 900)
        let scrollView = try #require(fixture.host.view.firstSubview(of: UIScrollView.self) { !($0 is UICollectionView) })
        scrollView.setContentOffset(CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.height), animated: false)
        fixture.host.view.layoutIfNeeded()
        for collection in fixture.collections where collection.window != nil {
            let frame = collection.convert(collection.bounds, to: nil)
            guard frame.intersects(fixture.window.bounds) else { continue }

            collection.layoutIfNeeded()
            let layout = try #require(collection.collectionViewLayout as? UICollectionViewFlowLayout)
            let stack = try #require(collection.superview)
            #expect(abs(collection.bounds.width - stack.bounds.width) < 0.5, "Visible rows are laid out at the current width")
            let first = try #require(collection.visibleCells.min { $0.frame.minX < $1.frame.minX })
            #expect(abs(first.frame.width - layout.itemSize.width) < 0.001)
            #expect(abs(first.frame.height - collection.bounds.height) < 1)
        }
    }

    @Test(arguments: [false, true])
    func `animated sidebar interpolates without breakpoint jumps`(perFrameEnvironment: Bool) async throws {
        let fixture = AdaptiveRowsFixture(perFrameEnvironment: perFrameEnvironment)
        fixture.layOut(width: 1180)
        fixture.scrollSecondRow(toItem: 10)
        try await Task.sleep(for: .milliseconds(100))

        for padding: CGFloat in [320, 0, 320, 0] {
            let report = try await fixture.recordAnimation {
                fixture.state.padding = padding
            }

            #expect(report.maximumHeightMismatch < 1, "Rows and their cells must agree on height every frame")
            #expect(report.maximumAnchorDrift < 1, "A scrolled row keeps its leading item aligned")
            #expect(report.itemWidthReversals == 0, "Animated resizing must not jump at intermediate column breakpoints")
        }
    }
}

// MARK: - Fixture

@MainActor
@Observable
final class AdaptiveRowsState {
    var padding: CGFloat = 0
}

@MainActor
final class AdaptiveRowsFixture {
    let rowCount: Int
    let state = AdaptiveRowsState()
    let host: UIHostingController<AnyView>
    let window: UIWindow
    private var samples: [[RowSample]] = []

    struct RowSample {
        let itemWidth: CGFloat
        let heightMismatch: CGFloat
        let anchorDrift: CGFloat?
    }

    init(perFrameEnvironment: Bool = true, rowCount: Int = 6, height: CGFloat = 1600) {
        self.rowCount = rowCount
        host = UIHostingController(rootView: AnyView(AdaptiveRowsRoot(
            state: state,
            rowCount: rowCount,
            perFrameEnvironment: perFrameEnvironment
        )))
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: height))
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    deinit {
        MainActor.assumeIsolated { window.isHidden = true }
    }

    var collections: [UICollectionView] {
        var result: [UICollectionView] = []
        func visit(_ view: UIView) {
            if let collection = view as? UICollectionView {
                result.append(collection)
                return
            }
            view.subviews.forEach(visit)
        }
        visit(host.view)
        return result.sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
    }

    func layOut(width: CGFloat) {
        window.frame.size.width = width
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    func scrollSecondRow(toItem item: Int) {
        let collection = collections[1]
        let attributes = collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: item, section: 0))!
        let layout = collection.collectionViewLayout as! UICollectionViewFlowLayout
        collection.setContentOffset(CGPoint(x: attributes.frame.minX - layout.sectionInset.left, y: 0), animated: false)
        collection.layoutIfNeeded()
    }

    func sample() {
        samples.append(collections.enumerated().map { index, collection in
            collection.layoutIfNeeded()
            let layout = collection.collectionViewLayout as! UICollectionViewFlowLayout
            let visible = collection.visibleCells.sorted { $0.frame.minX < $1.frame.minX }
            let first = visible.first
            let mismatch = first.map { abs($0.frame.height - collection.bounds.height) } ?? 0
            var drift: CGFloat?
            if index == 1, let anchor = layout.layoutAttributesForItem(at: IndexPath(item: 10, section: 0)) {
                drift = abs(anchor.frame.minX - collection.contentOffset.x - layout.sectionInset.left)
            }
            return RowSample(itemWidth: first?.frame.width ?? 0, heightMismatch: mismatch, anchorDrift: drift)
        })
    }

    /// Each width is one frame of a live window resize, laid out and committed synchronously.
    func recordLiveResize(widths: [CGFloat]) -> AdaptiveResizeReport {
        samples = []
        for width in widths {
            layOut(width: width)
            CATransaction.flush()
            sample()
        }
        return AdaptiveResizeReport(samples: samples)
    }

    /// Samples each snap frame, then lets it settle before the next.
    func recordSnaps(widths: [CGFloat]) async throws -> AdaptiveResizeReport {
        samples = []
        for width in widths {
            layOut(width: width)
            CATransaction.flush()
            sample()
            try await Task.sleep(for: .milliseconds(300))
        }
        return AdaptiveResizeReport(samples: samples)
    }

    func recordAnimation(change: () -> Void) async throws -> AdaptiveResizeReport {
        samples = []
        withAnimation(.smooth(duration: 0.35), change)
        for _ in 0 ..< 40 {
            try await Task.sleep(for: .milliseconds(12))
            sample()
        }
        return AdaptiveResizeReport(samples: samples)
    }
}

struct AdaptiveResizeReport {
    let samples: [[AdaptiveRowsFixture.RowSample]]

    var maximumHeightMismatch: CGFloat {
        samples.flatMap { $0.map(\.heightMismatch) }.max() ?? 0
    }

    var maximumAnchorDrift: CGFloat {
        samples.flatMap { $0.compactMap(\.anchorDrift) }.max() ?? 0
    }

    /// Item widths should change monotonically while the container moves in one direction.
    var itemWidthReversals: Int {
        guard let rows = samples.first?.count else { return 0 }

        var reversals = 0
        for row in 0 ..< rows {
            let widths = samples.map { $0[row].itemWidth }.filter { $0 > 0 }
            var direction: CGFloat = 0
            for (previous, next) in zip(widths, widths.dropFirst()) where abs(next - previous) > 0.25 {
                let step: CGFloat = next > previous ? 1 : -1
                if direction != 0, step != direction {
                    reversals += 1
                }
                direction = step
            }
        }
        return reversals
    }
}

extension UIView {
    func firstSubview<T: UIView>(of type: T.Type, where predicate: (T) -> Bool = { _ in true }) -> T? {
        for subview in subviews {
            if let match = subview as? T, predicate(match) {
                return match
            }
            if let match = subview.firstSubview(of: type, where: predicate) {
                return match
            }
        }
        return nil
    }
}

// MARK: - Views

private struct ContainerWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var adaptiveRowsContainerWidth: CGFloat {
        get { self[ContainerWidthKey.self] }
        set { self[ContainerWidthKey.self] = newValue }
    }
}

private struct AdaptiveRowsRoot: View {
    let state: AdaptiveRowsState
    let rowCount: Int
    let perFrameEnvironment: Bool

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0 ..< rowCount, id: \.self) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Section \(row)").font(.title3.bold()).padding(.horizontal, 24)
                        AdaptiveRow(landscape: row % 3 == 0)
                    }
                }
            }
        }
    }

    var body: some View {
        if perFrameEnvironment {
            // The container width follows each animation frame.
            GeometryReader { geometry in
                rows.environment(\.adaptiveRowsContainerWidth, geometry.size.width)
            }
            .padding(.leading, state.padding)
            .ignoresSafeArea()
        } else {
            // The container width is the destination, as when an app reads its window size.
            GeometryReader { geometry in
                rows
                    .environment(\.adaptiveRowsContainerWidth, geometry.size.width - state.padding)
                    .padding(.leading, state.padding)
            }
            .ignoresSafeArea()
        }
    }
}

private struct AdaptiveRow: View {
    @Environment(\.adaptiveRowsContainerWidth)
    private var containerWidth

    let landscape: Bool

    var body: some View {
        let compact = containerWidth > 0 && containerWidth < 600
        let minimumWidth: CGFloat = landscape ? (compact ? 220 : 300) : (compact ? 160 : 200)
        CollectionHStack(
            uniqueElements: Array(0 ..< 40),
            layout: .minimumWidth(columnWidth: minimumWidth, rows: 1, columnFraction: 0.5)
        ) { index in
            AdaptiveCard(index: index, landscape: landscape) { _ = containerWidth }
        }
        .clipsToBounds(false)
        .insets(horizontal: compact ? 16 : 24)
        .itemSpacing(10)
        .scrollBehavior(.continuousLeadingEdge)
        .contentInsetAdjustmentBehavior(.never)
    }
}

/// Shaped like a media poster button: artwork with overlays, a matched transition
/// source, hover and context menu effects, geometry tracking, and an action closure,
/// which makes every re-render evaluate the card's body.
private struct AdaptiveCard: View {
    @Namespace
    private var namespace
    @State
    private var size: CGSize = .zero

    let index: Int
    let landscape: Bool
    var action: () -> Void = {}

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            .aspectRatio(landscape ? 16 / 9 : 2 / 3, contentMode: .fit)
            .overlay {
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.circle.fill").padding(4)
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(.white)
                    .frame(width: max(0, size.width * 0.4), height: 4)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.contextMenuPreview, Rectangle())
            .matchedTransitionSource(id: "item", in: namespace)
            .shadow(radius: 2)
            .hoverEffect(.highlight)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                artwork
                Text("Title \(index)").font(.footnote).lineLimit(1)
                Text("2024 · Drama").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.borderless)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Play", systemImage: "play.fill") {}
            Button("Mark Played", systemImage: "checkmark") {}
        }
    }
}
#endif
