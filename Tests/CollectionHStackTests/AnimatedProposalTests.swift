#if os(iOS)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct AnimatedProposalTests {
    @Test(arguments: [120.0, 300.0], [false, true])
    func `animated padding interpolates cards without a width hint`(minimumWidth: CGFloat, retainedContent: Bool) async throws {
        let state = SidebarState()
        let row = SidebarFixture(state: state, minimumWidth: minimumWidth)
        let root = retainedContent
            ? AnyView(SidebarPadding(state: state, content: row.row))
            : AnyView(row)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let collection = try #require(findCollection(in: host.view))
        let stack = try #require(collection.superview)
        let first = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        let metrics = LayoutMetrics(
            layout: .minimumWidth(columnWidth: minimumWidth, rows: 1, columnFraction: 0.5),
            insets: .init(top: 0, leading: 24, bottom: 0, trailing: 24), itemSpacing: 10
        )

        func resize(to padding: CGFloat, samples: Int = 65) async throws {
            let targetWidth = 1180 - padding
            let targetItemWidth = try #require(metrics.itemWidth(for: targetWidth))
            let targetHost = UIHostingController(rootView: SidebarCard().frame(width: targetItemWidth).fixedSize(
                horizontal: false,
                vertical: true
            ))
            let targetItemSize = targetHost.sizeThatFits(in: CGSize(width: targetItemWidth, height: 1000))
            let sourceWidth = stack.bounds.width
            let sourceItemSize = first.frame.size
            state.padding = padding
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            var intermediateSamples = 0
            for _ in 0 ..< samples {
                try await Task.sleep(for: .milliseconds(16))
                host.view.layoutIfNeeded()
                collection.layoutIfNeeded()
                let progress = (stack.bounds.width - sourceWidth) / (targetWidth - sourceWidth)
                if progress > 0.01, progress < 0.99 {
                    intermediateSamples += 1
                    let expectedWidth = sourceItemSize.width + (targetItemWidth - sourceItemSize.width) * progress
                    let expectedHeight = sourceItemSize.height + (targetItemSize.height - sourceItemSize.height) * progress
                    #expect(abs(first.frame.width - expectedWidth) < 0.5)
                    #expect(abs(first.frame.height - expectedHeight) < 1)
                }
                #expect(collection.cellForItem(at: IndexPath(item: 0, section: 0)) === first)
                #expect(collection.visibleCells.count < 30)
                #expect(collection.adjustedContentInset.left == 0)
                #expect(abs(collection.convert(first.frame, to: stack).minX - 24) < 0.5)
            }
            #expect(intermediateSamples > 0)
            if samples == 65 {
                #expect(abs(stack.bounds.width - targetWidth) < 0.5)
                #expect(abs(first.frame.width - targetItemWidth) < 0.5)
            }
        }

        try await resize(to: 320)
        try await resize(to: 0)
        try await resize(to: 320, samples: 4)
        try await resize(to: 0)
        try await resize(to: 320, samples: 3)
        try await resize(to: 200)
    }

    private func findCollection(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView {
            return collection
        }
        return view.subviews.lazy.compactMap { findCollection(in: $0) }.first
    }
}

@MainActor
@Observable
private final class SidebarState {
    var padding: CGFloat = 0
}

private struct SidebarFixture: View {
    let state: SidebarState
    let minimumWidth: CGFloat

    var row: some View {
        ScrollView {
            CollectionHStack(
                uniqueElements: Array(0 ..< 200),
                layout: .minimumWidth(columnWidth: minimumWidth, rows: 1, columnFraction: 0.5)
            ) { _ in
                SidebarCard()
            }
            .insets(horizontal: 24)
            .itemSpacing(10)
            .scrollBehavior(.continuousLeadingEdge)
            .contentInsetAdjustmentBehavior(.never)
        }
    }

    var body: some View {
        row
            .padding(.leading, state.padding)
            .animation(.smooth(duration: 0.35), value: state.padding)
            .ignoresSafeArea()
    }
}

private struct SidebarPadding<Content: View>: View {
    let state: SidebarState
    let content: Content

    var body: some View {
        content
            .padding(.leading, state.padding)
            .animation(.smooth(duration: 0.35), value: state.padding)
            .ignoresSafeArea()
    }
}

private struct SidebarCard: View {
    var body: some View {
        VStack {
            Color.blue.aspectRatio(16 / 9, contentMode: .fit)
            Text("Poster title").lineLimit(1).frame(height: 24)
        }
    }
}
#endif
