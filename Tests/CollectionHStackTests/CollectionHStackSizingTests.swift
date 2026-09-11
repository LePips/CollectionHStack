#if canImport(UIKit)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionHStackSizingTests {

    @Test
    func contentMeasurementIsCachedAcrossResizeWidths() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)

        _ = stack.fittingSize(forWidth: 210)
        _ = stack.fittingSize(forWidth: 210)

        #expect(counter.value == 1)

        _ = stack.fittingSize(forWidth: 410)

        #expect(counter.value == 1)
    }

    @Test
    func measuredProportionsDetermineHeightForEveryResizeWidth() {
        let stack = makeAspectRatioStack()

        let initialSize = stack.fittingSize(forWidth: 210)
        let widerSize = stack.fittingSize(forWidth: 410)
        let intermediateSize = stack.fittingSize(forWidth: 310)
        let restoredSize = stack.fittingSize(forWidth: 210)

        #expect(initialSize == CGSize(width: 210, height: 150))
        #expect(widerSize == CGSize(width: 410, height: 300))
        #expect(intermediateSize == CGSize(width: 310, height: 225))
        #expect(restoredSize == CGSize(width: 210, height: 150))
    }

    @Test
    func fractionalWidthMeasurementPreservesContentProportions() {
        let stack = makeAspectRatioStack()
        #expect(abs(stack.fittingSize(forWidth: 550 / 3).height - 130) <= 0.001)
        #expect(abs(stack.fittingSize(forWidth: 810).height - 600) <= 0.001)
    }

    @Test
    func dataChangesAndDynamicTypeRemeasureContent() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)
        #expect(stack.fittingSize(forWidth: 210).height == 50)
        #expect(stack.fittingSize(forWidth: 410).height == 100)
        stack.update(
            newData: [1], alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        )
        #expect(stack.fittingSize(forWidth: 410).height == 50)
        #expect(counter.value == 2)
        stack.traitCollectionDidChange(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        #expect(stack.fittingSize(forWidth: 210).height == 50)
        #expect(counter.value == 3)
    }

    @Test
    func selfSizingLayoutsKeepTheirMeasuredDimensionsWhileResizing() {
        for layout: CollectionHStackLayout in [.selfSizingSameSize(rows: 1), .selfSizingVariadicWidth(rows: 1)] {
            let stack = makeStack(counter: MeasurementCounter(), layout: layout)
            let initialSize = stack.computeSizes(forWidth: 210)
            let resizedSize = stack.computeSizes(forWidth: 410)
            #expect(initialSize.itemSize == resizedSize.itemSize)
            #expect(resizedSize.selfSize.height == 50)
        }
    }

    @Test
    func zeroWidthDoesNotCreateAMeasurement() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)
        #expect(stack.computeSizes(forWidth: 0).selfSize.height == 0)
        #expect(counter.value == 0)
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 50)
        #expect(stack.computeSizes(forWidth: 410).selfSize.height == 100)
        #expect(counter.value == 1)
    }

    @Test
    func zeroHeightDoesNotCacheInvalidProportions() {
        let counter = MeasurementCounter()
        counter.height = 0
        let stack = makeStack(counter: counter)
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 0)
        counter.height = 50
        #expect(stack.computeSizes(forWidth: 410).selfSize.height == 50)
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 25)
        #expect(counter.value == 2)
    }

    @Test
    func emptyCollectionMeasuresWhenDataArrives() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter, data: [])
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 0)
        #expect(counter.value == 0)
        stack.update(
            newData: [0], alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        )
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 50)
        #expect(stack.computeSizes(forWidth: 410).selfSize.height == 100)
        #expect(counter.value == 1)
    }

    @Test
    func resizeDerivesProportionsFromMeasuredContent() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)

        let initialSize = stack.fittingSize(forWidth: 210)
        let resizedSize = stack.fittingSize(forWidth: 410)

        #expect(initialSize == CGSize(width: 210, height: 50))
        #expect(resizedSize == CGSize(width: 410, height: 100))
        #expect(counter.value == 1)
    }

    @Test
    func proxyRedrawRemeasuresAContentDefinedAspectRatio() {
        let aspectRatio = MutableAspectRatio(2 / 3)
        let proxy = CollectionHStackProxy()
        let stack = makeMutableAspectRatioStack(aspectRatio: aspectRatio, proxy: proxy)

        #expect(stack.fittingSize(forWidth: 210) == CGSize(width: 210, height: 150))

        aspectRatio.value = 1
        #expect(stack.fittingSize(forWidth: 410) == CGSize(width: 410, height: 300))
        proxy.redraw()

        #expect(stack.fittingSize(forWidth: 210) == CGSize(width: 210, height: 100))
        #expect(stack.fittingSize(forWidth: 410) == CGSize(width: 410, height: 200))
        aspectRatio.value = 2
        proxy.redraw()
        #expect(stack.fittingSize(forWidth: 410) == CGSize(width: 410, height: 100))
    }

    @Test
    func widthOnlyResizeUpdatesTheResolvedItemWidth() throws {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)

        stack.bounds = CGRect(x: 0, y: 0, width: 210, height: 50)
        stack.layoutSubviews()
        let collectionView = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        let initialItemSize = stack.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        stack.bounds.size.width = 210.2
        stack.layoutSubviews()
        let resizedItemSize = stack.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        #expect(initialItemSize.width == 100)
        #expect(abs(initialItemSize.height - 50) <= 0.001)
        #expect(abs(resizedItemSize.width - 100.1) <= 0.001)
        #expect(abs(resizedItemSize.height - 50.05) <= 0.001)
    }

    @Test
    func swiftUIFittingProposalDoesNotOverwriteLiveUIKitItemSize() throws {
        let stack = makeStack(
            counter: MeasurementCounter(),
            isCarousel: true
        )
        stack.bounds = CGRect(x: 0, y: 0, width: 375, height: 50)
        stack.layoutSubviews()

        let collectionView = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        let liveSizeBeforeProposal = stack.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        let proposedSize = stack.fittingSize(forWidth: 506)
        let liveSizeAfterProposal = stack.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )

        #expect(proposedSize.width == 506)
        #expect(abs(proposedSize.height - (50 * 248 / 182.5)) <= 0.001)
        #expect(liveSizeBeforeProposal.width == 182.5)
        #expect(liveSizeAfterProposal == liveSizeBeforeProposal)
        #expect(collectionView.flowLayout.itemSize == liveSizeBeforeProposal)
        #expect(try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )
        ).size == liveSizeBeforeProposal)

        stack.bounds.size.width = 506
        stack.layoutSubviews()

        #expect(collectionView.flowLayout.itemSize.width == 248)
        #expect(try #require(
            collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: 0, section: 0)
            )
        ).size.width == 248)

        let liveSizeAfterBoundsChange = stack.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )
        #expect(liveSizeAfterBoundsChange.width == 248)
    }

    @Test
    func minimumWidthUsesOneColumnWhenTheContainerIsNarrowerThanTheMinimum() {
        let counter = MeasurementCounter()
        let stack = makeStack(
            counter: counter,
            layout: .minimumWidth(columnWidth: 200, rows: 1)
        )

        let size = stack.computeSizes(forWidth: 100)

        #expect(size.itemSize.width == 100)
        #expect(abs(size.itemSize.height - 50) <= 0.001)
        #expect(size.selfSize.height == 50)
    }

    @Test
    func invalidRowCountUsesOneRow() {
        let stack = makeStack(
            counter: MeasurementCounter(),
            layout: .grid(columns: 2, rows: 0, columnTrailingInset: 0)
        )

        let size = stack.computeSizes(forWidth: 210)

        #expect(size.selfSize.height == 50)
        #expect(size.itemSize.width == 100)
        #expect(abs(size.itemSize.height - 50) <= 0.001)
    }

    @Test
    func largeCollectionResizeReusesInitialMeasurement() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter, data: Array(0 ..< 10000))
        for step in 0 ..< 120 {
            let width = CGFloat(320 + step * 8)
            _ = stack.fittingSize(forWidth: width)
        }
        #expect(counter.value == 1, "Resizing must reuse the initial content measurement")
    }

    @Test
    func insetsAndSpacingUpdateWithoutChangingContainerWidth() throws {
        let stack = makeStack(counter: MeasurementCounter())
        _ = stack.fittingSize(forWidth: 210)
        stack.update(
            newData: [0], alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0),
            insets: .init(top: 5, leading: 20, bottom: 5, trailing: 30),
            itemSpacing: 20
        )
        #expect(stack.fittingSize(forWidth: 210).height == 60)
        stack.bounds = CGRect(x: 0, y: 0, width: 210, height: 60)
        stack.layoutSubviews()
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.flowLayout.itemSize.width == 70)
        #expect(collection.flowLayout.sectionInset.left == 20)
        #expect(collection.flowLayout.sectionInset.right == 30)
    }

    @Test
    func redrawUsesUpdatedContentProvider() {
        let original = MeasurementCounter()
        let replacement = MeasurementCounter()
        let stack = makeStack(counter: original)
        _ = stack.fittingSize(forWidth: 210)
        stack.update(
            newData: [0], alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0),
            viewProvider: { _ in MeasuredItem(counter: replacement) }
        )
        stack.snapshotReload()
        _ = stack.fittingSize(forWidth: 210)
        #expect(original.value == 1)
        #expect(replacement.value > 0)
    }

    private func makeStack(
        counter: MeasurementCounter,
        layout: CollectionHStackLayout = .grid(columns: 2, rows: 1, columnTrailingInset: 0),
        isCarousel: Bool = false,
        data: [Int] = [0]
    ) -> UICollectionHStack<Int, [Int], Int, MeasuredItem> {
        UICollectionHStack(
            id: \.self,
            alignedLeadingElementID: nil,
            clipsToBounds: true,
            data: data,
            dataPrefix: nil,
            didScrollToItems: { _ in },
            insets: .init(),
            isCarousel: isCarousel,
            itemSpacing: 10,
            layout: layout,
            onReachedLeadingEdge: {},
            onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {},
            onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in },
            onCancelPrefetchingElements: { _ in },
            proxy: .init(),
            scrollBehavior: .continuous,
            viewProvider: { _ in MeasuredItem(counter: counter) }
        )
    }

    private func makeAspectRatioStack() -> UICollectionHStack<Int, [Int], Int, AspectRatioItem> {
        UICollectionHStack(
            id: \.self,
            alignedLeadingElementID: nil,
            clipsToBounds: true,
            data: [0],
            dataPrefix: nil,
            didScrollToItems: { _ in },
            insets: .init(),
            isCarousel: false,
            itemSpacing: 10,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0),
            onReachedLeadingEdge: {},
            onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {},
            onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in },
            onCancelPrefetchingElements: { _ in },
            proxy: .init(),
            scrollBehavior: .continuous,
            viewProvider: { _ in AspectRatioItem() }
        )
    }

    private func makeMutableAspectRatioStack(
        aspectRatio: MutableAspectRatio,
        proxy: CollectionHStackProxy
    ) -> UICollectionHStack<Int, [Int], Int, MutableAspectRatioItem> {
        UICollectionHStack(
            id: \.self,
            alignedLeadingElementID: nil,
            clipsToBounds: true,
            data: [0],
            dataPrefix: nil,
            didScrollToItems: { _ in },
            insets: .init(),
            isCarousel: false,
            itemSpacing: 10,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0),
            onReachedLeadingEdge: {},
            onReachedLeadingEdgeOffset: .columns(0),
            onReachedTrailingEdge: {},
            onReachedTrailingEdgeOffset: .columns(0),
            onPrefetchingElements: { _ in },
            onCancelPrefetchingElements: { _ in },
            proxy: proxy,
            scrollBehavior: .continuous,
            viewProvider: { _ in MutableAspectRatioItem(aspectRatio: aspectRatio.value) }
        )
    }
}

private final class MeasurementCounter {
    var value = 0
    var height: CGFloat = 50
}

private struct MeasuredItem: View {
    private let height: CGFloat

    init(counter: MeasurementCounter) {
        counter.value += 1
        height = counter.height
    }

    var body: some View {
        Color.blue.frame(height: height)
    }
}

private struct AspectRatioItem: View {
    var body: some View {
        Color.blue.aspectRatio(2 / 3, contentMode: .fill)
    }
}

private final class MutableAspectRatio {
    var value: CGFloat

    init(_ value: CGFloat) {
        self.value = value
    }
}

private struct MutableAspectRatioItem: View {
    let aspectRatio: CGFloat

    var body: some View {
        Color.blue.aspectRatio(aspectRatio, contentMode: .fill)
    }
}

#endif
