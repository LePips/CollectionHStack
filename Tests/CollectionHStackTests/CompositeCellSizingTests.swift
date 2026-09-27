@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CompositeCellSizingTests {
    @Test(arguments: 0 ..< 4, 0 ..< 3)
    func resizingMeasuresArtworkAndTextAtTheNewWidth(style: Int, layoutIndex: Int) throws {
        let layout: CollectionHStackLayout = [
            .grid(columns: 1, rows: 1, columnTrailingInset: 0),
            .grid(columns: 3, rows: 2, columnTrailingInset: 0),
            .minimumWidth(columnWidth: 140, rows: 2, columnFraction: 0.5),
        ][layoutIndex]
        let configuration = CollectionHStack(uniqueElements: Array(0 ..< 20), layout: layout) { _ in
            CompositeCell(style: style)
        }.insets(horizontal: 18, vertical: 5).itemSpacing(10)
        let metrics = LayoutMetrics(layout: layout, insets: configuration.insets, itemSpacing: 10)
        #if os(macOS)
        let stack = NSCollectionHStack(configuration: configuration)
        defer { stack.disconnect() }
        #else
        let stack = UICollectionHStack(
            id: \.self, alignedLeadingElementID: nil, clipsToBounds: true,
            data: Array(0 ..< 20), dataPrefix: nil, didScrollToItems: { _ in },
            insets: configuration.insets, isCarousel: false, itemSpacing: 10, layout: layout,
            onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: .init(), scrollBehavior: .continuous,
            viewProvider: { _ in CompositeCell(style: style) }
        )
        #endif

        for width: CGFloat in [320, 768, 414, 1024, 249.9, 250, 320] {
            let itemWidth = try #require(metrics.itemWidth(for: width))
            let content = CompositeCell(style: style)
                .frame(width: itemWidth)
                .fixedSize(horizontal: false, vertical: true)
            #if os(macOS)
            let host = NSHostingController(rootView: content)
            #else
            let host = UIHostingController(rootView: content)
            #endif
            let expected = host.sizeThatFits(in: CGSize(width: itemWidth, height: .greatestFiniteMagnitude))
            let sizes = stack.computeSizes(forWidth: width)
            #expect(abs(sizes.itemSize.width - itemWidth) < 0.001)
            #expect(abs(sizes.itemSize.height - expected.height) < 1)
            #expect(abs(sizes.selfSize.height - metrics.height(for: expected)) < CGFloat(metrics.rows))
        }
    }
}

/// Matches the artwork/text arrangements in App Store Apps and Apple Music Genre,
/// plus a wrapping caption whose height changes nonlinearly with the available width.
struct CompositeCell: View {
    let style: Int

    var body: some View {
        VStack(alignment: .leading, spacing: style == 2 ? 8 : 2) {
            if style == 0 || style == 1 {
                Text("FEATURED")
                    .font(.caption2)
                    .lineLimit(1)
                Text("A favorite worth discovering")
                    .font(style == 0 ? .title2 : .title)
                    .lineLimit(1)
                if style == 0 {
                    Text("Made for every day")
                        .font(.title2)
                        .lineLimit(1)
                        .padding(.bottom, 5)
                }
            }

            Color.blue
                .aspectRatio(style == 2 ? 1 : 1.77, contentMode: .fill)

            if style == 2 {
                Text("Favorite album").lineLimit(1)
                Text("Featured artist").lineLimit(1)
            } else if style == 3 {
                Text("Discover a collection of favorite albums and new releases selected for every part of your day.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
