#if os(iOS)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct ResizeBehaviorTests {

    // MARK: content refresh

    @Test
    func `content updates during a resize reach visible cells once the width settles`() async throws {
        let state = RefreshState()
        let host = UIHostingController(rootView: RefreshFixture(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let collection = try #require(findCollection(in: host.view))
        let visible = { collection.indexPathsForVisibleItems.map(\.item) }

        // Without a resize, new content reaches every visible cell in the same pass.
        state.label = "B"
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(visible().allSatisfy { state.provided[$0] == "B" })

        // An adaptive parent re-renders each row on every resize frame. Retained cells
        // are only laid out at their new size until the width settles.
        state.label = "C"
        state.padding = 120
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(visible().contains { state.provided[$0] == "B" }, "Retained cells keep their content while resizing")
        try await Task.sleep(for: .milliseconds(250))
        host.view.layoutIfNeeded()
        #expect(visible().allSatisfy { state.provided[$0] == "C" })
    }

    // MARK: scroll anchoring

    @Test(arguments: 0 ..< 4)
    func `resizing preserves the scroll position for each scroll behavior`(behaviorIndex: Int) throws {
        let behavior: CollectionHStackScrollBehavior = [.continuous, .continuousLeadingEdge, .columnPaging, .fullPaging][behaviorIndex]
        let (stack, collection, window) = makeStack(behavior: behavior)
        defer { window.isHidden = true }
        let layout = try #require(collection.collectionViewLayout as? CollectionHStackFlowLayout)

        func layOut(width: CGFloat) {
            stack.frame.size = CGSize(width: width, height: stack.fittingSize(forWidth: width).height)
            stack.layoutIfNeeded()
            collection.layoutIfNeeded()
        }

        layOut(width: 900)
        if let paging = layout as? FullPagingFlowLayout {
            // Paging rests on page boundaries; item 30 lies within the fourth page.
            collection.contentOffset.x = paging.pageSize * 3
        } else {
            stack.scrollTo(index: 30, animated: false)
        }
        collection.layoutIfNeeded()
        let originalOffset = collection.contentOffset.x

        // The anchor is recorded once, so a sweep back to the original width
        // returns to the exact original offset without accumulated rounding.
        let widths = Array(stride(from: CGFloat(899.5), through: 520, by: -7.3)) + Array(stride(
            from: CGFloat(520),
            through: 900,
            by: 11.1
        )) + [900]
        for width in widths {
            layOut(width: width)
            let viewport = layout.viewportBounds(at: collection.contentOffset)
            let target = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 30, section: 0)))
            switch behavior {
            case .continuous:
                // Scroll views align their offsets to device pixels.
                let pixel = 1 / max(collection.traitCollection.displayScale, 1)
                #expect(abs(target.frame.midX - viewport.midX) <= pixel, "The centered item stays centered at \(width)")

            case .continuousLeadingEdge, .columnPaging:
                #expect(
                    abs(target.frame.minX - layout.sectionInset.left - collection.contentOffset.x) < 0.01,
                    "The leading column stays aligned at \(width)"
                )

            case .fullPaging:
                let paging = try #require(layout as? FullPagingFlowLayout)
                let page = collection.contentOffset.x / paging.pageSize
                #expect(abs(page - page.rounded()) < 0.001, "Paging stays on a page boundary at \(width)")
            }
        }
        #expect(abs(collection.contentOffset.x - originalOffset) < 0.001)

        // Scrolling records a new position; the leading and trailing edges stay pinned.
        collection.contentOffset.x = 0
        layOut(width: 700)
        #expect(collection.contentOffset.x == 0)
        stack.scrollTo(index: 99, animated: false)
        collection.layoutIfNeeded()
        layOut(width: 860)
        let maximum = collection.contentSize.width - collection.bounds.width
        #expect(abs(collection.contentOffset.x - maximum) < 0.001)
    }

    // MARK: offscreen rows

    @Test
    func `rows far outside the window resize when needed`() throws {
        let proxies = (0 ..< 10).map { _ in CollectionHStackProxy() }
        let host = UIHostingController(rootView: OffscreenRows(proxies: proxies))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 500))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        let collections = host.view
            .allSubviews(of: UICollectionView.self)
            .sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
        #expect(collections.count == 10)
        let first = try #require(collections.first)
        let collection = try #require(collections.last)
        let last = try #require(collection.superview)
        let deferredWidth = collection.bounds.width

        window.frame.size.width = 760
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        #expect(abs(first.bounds.width - (try #require(first.superview)).bounds.width) < 0.5)
        #expect(last.bounds.width < deferredWidth)
        #expect(collection.bounds.width == deferredWidth, "The last row is far outside the window")

        // Scrolling a deferred row through its proxy first applies the current width.
        proxies[9].scrollTo(index: 20, animated: false)
        let layout = try #require(collection.collectionViewLayout as? UICollectionViewFlowLayout)
        #expect(abs(collection.bounds.width - last.bounds.width) < 0.5)
        let target = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 20, section: 0)))
        #expect(abs(target.frame.minX - layout.sectionInset.left - collection.contentOffset.x) < 0.5)
    }

    // MARK: animated proposals

    /// Containers that update the row on every animation frame re-arm its transition
    /// just before the next proposal, which may lie only a few points from the current
    /// width. SwiftUI can then propose a distant width in the same frame.
    @Test(arguments: [(1099.0, 1376.0), (1093.0, 760.0), (1096.4, 1376.0), (1095.9, 600.0)])
    func `proposals outside an animation's span use exact sizes`(near: CGFloat, far: CGFloat) throws {
        let (stack, collection, window) = makeStack(behavior: .continuousLeadingEdge)
        defer { window.isHidden = true }
        let (reference, _, referenceWindow) = makeStack(behavior: .continuousLeadingEdge)
        defer { referenceWindow.isHidden = true }

        stack.frame.size = CGSize(width: 1096, height: stack.fittingSize(forWidth: 1096).height)
        stack.layoutIfNeeded()
        collection.layoutIfNeeded()

        stack.prepareForLayout()
        _ = stack.fittingSize(forProposedWidth: near)
        let proposed = stack.fittingSize(forProposedWidth: far)
        let exact = reference.fittingSize(forWidth: far)
        #expect(abs(proposed.height - exact.height) <= 0.5, "Height at \(far) was \(proposed.height), expected \(exact.height)")

        // The live layout at that width must not extrapolate either.
        stack.frame.size = CGSize(width: far, height: proposed.height)
        stack.layoutIfNeeded()
        collection.layoutIfNeeded()
        let cell = try #require(collection.visibleCells.first)
        #expect(cell.frame.height > 0)
        #expect(abs(cell.frame.height - exact.height) <= 1)
    }

    /// SwiftUI proposes each animation frame both before and after pixel alignment,
    /// and the aligned duplicate lies slightly closer to the source. Neither may be
    /// taken for a new destination: a transition spanning a single frame extrapolates
    /// the next frames and destination probes far outside both layouts.
    @Test(arguments: [(1376.0, 1096.0), (1096.0, 1376.0)])
    func `animation frames do not retarget the size transition`(source: CGFloat, target: CGFloat) throws {
        let (stack, collection, window) = makeStack(behavior: .continuousLeadingEdge)
        defer { window.isHidden = true }

        func layOut(width: CGFloat) throws -> CGSize {
            stack.frame.size = CGSize(width: width, height: stack.fittingSize(forProposedWidth: width).height)
            stack.layoutIfNeeded()
            collection.layoutIfNeeded()
            return try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0))).frame.size
        }

        let targetItem = try layOut(width: target)
        let targetHeight = stack.bounds.height
        stack.prepareForLayout()
        let sourceItem = try layOut(width: source)
        let sourceHeight = stack.bounds.height
        func isBetweenEndpoints(_ value: CGFloat, _ source: CGFloat, _ target: CGFloat) -> Bool {
            value >= min(source, target) - 0.5 && value <= max(source, target) + 0.5
        }

        let pixel = 1 / max(stack.traitCollection.displayScale, 1)
        let omega = 2 * CGFloat.pi / 0.35
        stack.prepareForLayout()
        #expect(abs(stack.fittingSize(forProposedWidth: target).height - targetHeight) <= 0.5)
        for frame in 1 ... 72 {
            let time = CGFloat(frame) / 120
            let width = source + (target - source) * (1 - (1 + omega * time) * exp(-omega * time))
            let aligned = target > source ? (width / pixel).rounded(.down) * pixel : (width / pixel).rounded(.up) * pixel
            for proposal in [width, aligned] {
                let height = stack.fittingSize(forProposedWidth: proposal).height
                #expect(isBetweenEndpoints(height, sourceHeight, targetHeight), "Frame \(frame) proposed \(height) at \(proposal)")
            }
            let item = try layOut(width: aligned)
            #expect(isBetweenEndpoints(item.width, sourceItem.width, targetItem.width), "Frame \(frame) item \(item) at \(aligned)")
            #expect(isBetweenEndpoints(item.height, sourceItem.height, targetItem.height), "Frame \(frame) item \(item) at \(aligned)")

            let probe = stack.fittingSize(forProposedWidth: target).height
            #expect(abs(probe - targetHeight) <= 0.5, "Frame \(frame) destination probe was \(probe)")
        }

        let settled = try layOut(width: target)
        #expect(abs(settled.width - targetItem.width) < 0.001)
        #expect(abs(settled.height - targetItem.height) < 0.5)
    }

    // MARK: measurement

    @Test
    func `retained measurement matches a new hosting hierarchy at every width`() {
        let measurer = ContentMeasurer<MeasuredCard>()
        for (index, width) in [CGFloat(80), 133.3, 201.6, 342.67, 90.5, 512, 80].enumerated() {
            for title in ["Short", "A considerably longer title that wraps across several lines"] {
                let card = MeasuredCard(title: title)
                let retained = measurer.size(of: card, identity: AnyHashable(title), width: width)

                let fresh = ContentMeasurement()
                let controller = UIHostingController(rootView: ContentMeasurementLayout(width: width, measurement: fresh) {
                    card.frame(width: width)
                })
                controller.safeAreaRegions.remove(.container)
                _ = controller.sizeThatFits(in: .zero)

                #expect(retained == fresh.size, "Measurement \(index) at \(width)")
            }
        }
    }

    // MARK: helpers

    private func makeStack(behavior: CollectionHStackScrollBehavior)
    -> (UICollectionHStack<Int, [Int], Int, some View>, UICollectionView, UIWindow) {
        let configuration = CollectionHStack(
            uniqueElements: Array(0 ..< 100),
            layout: .minimumWidth(columnWidth: 120, rows: 1, columnFraction: 0.5)
        ) { _ in
            Color.blue.aspectRatio(2 / 3, contentMode: .fit)
        }
        .insets(horizontal: 24)
        .itemSpacing(10)
        .scrollBehavior(behavior)

        let stack = UICollectionHStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: true,
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
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        window.rootViewController = controller
        controller.view.addSubview(stack)
        window.makeKeyAndVisible()
        let collection = stack.subviews.compactMap { $0 as? UICollectionView }.first!
        return (stack, collection, window)
    }

    private func findCollection(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView {
            return collection
        }
        return view.subviews.lazy.compactMap { findCollection(in: $0) }.first
    }
}

private struct OffscreenRows: View {
    let proxies: [CollectionHStackProxy]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(0 ..< proxies.count, id: \.self) { row in
                    CollectionHStack(count: 40, minWidth: 140, columnFraction: 0.5) { _ in
                        Color.blue.aspectRatio(2 / 3, contentMode: .fit)
                    }
                    .scrollBehavior(.continuousLeadingEdge)
                    .proxy(proxies[row])
                }
            }
        }
        .ignoresSafeArea()
    }
}

extension UIView {
    func allSubviews<T: UIView>(of type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            if let match = subview as? T {
                return [match]
            }
            return subview.allSubviews(of: type)
        }
    }
}

@MainActor
@Observable
private final class RefreshState {
    var label = "A"
    var padding: CGFloat = 0
    @ObservationIgnored
    var provided: [Int: String] = [:]
}

private struct RefreshFixture: View {
    let state: RefreshState

    private func card(_ index: Int, label: String) -> some View {
        state.provided[index] = label
        return Text("\(label) \(index)").frame(height: 80)
    }

    var body: some View {
        let label = state.label
        VStack {
            CollectionHStack(count: 40, minWidth: 120, columnFraction: 0.5) { index in
                card(index, label: label)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, state.padding)
        .ignoresSafeArea()
    }
}

private struct MeasuredCard: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.blue.aspectRatio(16 / 9, contentMode: .fit)
            Text(title).font(.footnote)
            Text("2024").font(.caption)
        }
        .padding(6)
    }
}
#endif
