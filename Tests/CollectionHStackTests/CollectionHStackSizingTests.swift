#if canImport(UIKit)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CollectionHStackSizingTests {

    @Test(arguments: 0 ..< 3)
    func `measurement revision refreshes cached widths and intrinsic height`(layoutIndex: Int) throws {
        let layout: CollectionHStackLayout = [
            .grid(columns: 2, rows: 2, columnTrailingInset: 0),
            .minimumWidth(columnWidth: 100, rows: 2),
            .selfSizingSameSize(rows: 2),
        ][layoutIndex]
        let original = MeasurementCounter()
        let replacement = MeasurementCounter()
        replacement.height = 75
        let stack = makeStack(counter: original, layout: layout)
        #expect(stack.fittingSize(forWidth: 210).height == 110)
        #expect(stack.fittingSize(forWidth: 410).height == 110)
        stack.frame = CGRect(x: 0, y: 0, width: 210, height: 110)
        stack.layoutIfNeeded()

        stack.update(
            newData: [0],
            alignedLeadingElementID: nil,
            layout: layout,
            itemMeasurementRevision: 1,
            viewProvider: { _ in MeasuredItem(counter: replacement) }
        )
        #expect(stack.fittingSize(forWidth: 210).height == 160)
        #expect(stack.fittingSize(forWidth: 410).height == 160)
        stack.layoutIfNeeded()
        #expect(stack.intrinsicContentSize.height == 160)
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(collection.flowLayout.itemSize.height == 75)

        stack.update(
            newData: [0],
            alignedLeadingElementID: nil,
            layout: layout,
            itemMeasurementRevision: 1
        )
        let measurements = replacement.value
        _ = stack.fittingSize(forWidth: 210)
        #expect(replacement.value == measurements, "The same revision reuses measurements")
    }

    @Test
    func `content measurement is cached for each resize width`() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)

        _ = stack.fittingSize(forWidth: 210)
        _ = stack.fittingSize(forWidth: 210)

        #expect(counter.value == 1)

        _ = stack.fittingSize(forWidth: 410)
        _ = stack.fittingSize(forWidth: 210)

        #expect(counter.value == 2)
    }

    @Test
    func `measured proportions determine height for every resize width`() {
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
    func `fractional width measurement preserves content proportions`() {
        let stack = makeAspectRatioStack()
        #expect(abs(stack.fittingSize(forWidth: 550 / 3).height - 130) <= 0.001)
        #expect(abs(stack.fittingSize(forWidth: 810).height - 600) <= 0.001)
    }

    @Test
    func `data changes remeasure content`() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)
        #expect(stack.fittingSize(forWidth: 210).height == 50)
        #expect(stack.fittingSize(forWidth: 410).height == 50)
        stack.update(
            newData: [1], alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        )
        #expect(stack.fittingSize(forWidth: 410).height == 50)
        #expect(counter.value == 3)
    }

    @Test
    func `dynamic type changes invalidate cached measurements`() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)
        stack.traitOverrides.preferredContentSizeCategory = .large

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 410, height: 200))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(stack)
        stack.frame = CGRect(x: 0, y: 0, width: 210, height: 50)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        #expect(stack.fittingSize(forWidth: 210).height == 50)
        #expect(stack.fittingSize(forWidth: 410).height == 50)
        let measurements = counter.value

        stack.traitOverrides.userInterfaceStyle = .dark
        stack.updateTraitsIfNeeded()
        #expect(stack.fittingSize(forWidth: 210).height == 50)
        #expect(counter.value == measurements, "Unrelated traits must preserve cached measurements")

        counter.height = 75
        stack.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        stack.updateTraitsIfNeeded()
        #expect(stack.fittingSize(forWidth: 210).height == 75)
        #expect(stack.fittingSize(forWidth: 410).height == 75)
        stack.frame.size.height = 75
        stack.layoutIfNeeded()
        #expect(stack.intrinsicContentSize.height == 75)
    }

    @Test
    func `self sizing layouts keep their measured dimensions while resizing`() {
        for layout: CollectionHStackLayout in [.selfSizingSameSize(rows: 1), .selfSizingVariadicWidth(rows: 1)] {
            let stack = makeStack(counter: MeasurementCounter(), layout: layout)
            let initialSize = stack.computeSizes(forWidth: 210)
            let resizedSize = stack.computeSizes(forWidth: 410)
            #expect(initialSize.itemSize == resizedSize.itemSize)
            #expect(resizedSize.selfSize.height == 50)
        }
    }

    @Test
    func `zero width does not create A measurement`() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)
        #expect(stack.computeSizes(forWidth: 0).selfSize.height == 0)
        #expect(counter.value == 0)
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 50)
        #expect(stack.computeSizes(forWidth: 410).selfSize.height == 50)
        #expect(counter.value == 2)
    }

    @Test
    func `zero height does not cache an incomplete measurement`() {
        let counter = MeasurementCounter()
        counter.height = 0
        let stack = makeStack(counter: counter)
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 0)
        counter.height = 50
        #expect(stack.computeSizes(forWidth: 410).selfSize.height == 50)
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 50)
        #expect(counter.value == 3)
    }

    @Test
    func `empty collection measures when data arrives`() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter, data: [])
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 0)
        #expect(counter.value == 0)
        stack.update(
            newData: [0], alignedLeadingElementID: nil,
            layout: .grid(columns: 2, rows: 1, columnTrailingInset: 0)
        )
        #expect(stack.computeSizes(forWidth: 210).selfSize.height == 50)
        #expect(stack.computeSizes(forWidth: 410).selfSize.height == 50)
        #expect(counter.value == 2)
    }

    @Test
    func `resize preserves fixed content height`() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter)

        let initialSize = stack.fittingSize(forWidth: 210)
        let resizedSize = stack.fittingSize(forWidth: 410)

        #expect(initialSize == CGSize(width: 210, height: 50))
        #expect(resizedSize == CGSize(width: 410, height: 50))
        #expect(counter.value == 2)
    }

    @Test
    func `proxy redraw remeasures A content defined aspect ratio`() {
        let aspectRatio = MutableAspectRatio(2 / 3)
        let proxy = CollectionHStackProxy()
        let stack = makeMutableAspectRatioStack(aspectRatio: aspectRatio, proxy: proxy)

        #expect(stack.fittingSize(forWidth: 210) == CGSize(width: 210, height: 150))
        #expect(stack.fittingSize(forWidth: 410) == CGSize(width: 410, height: 300))

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
    func `width only resize updates the resolved item width`() throws {
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
        #expect(abs(resizedItemSize.height - 50) <= 0.001)
    }

    @Test(arguments: [CGFloat(1), 2, 3], [CGFloat(139.83065744173726), 257.7357421875])
    func `single row items fit fractional collection bounds`(displayScale: CGFloat, itemHeight: CGFloat) throws {
        let counter = MeasurementCounter()
        counter.height = itemHeight
        let stack = makeStack(counter: counter)
        stack.traitOverrides.displayScale = displayScale
        var fittingSize = stack.fittingSize(forWidth: 402)
        fittingSize.height = (fittingSize.height * displayScale).rounded() / displayScale

        for origin: CGFloat in [0, 62, 301 / 3, 1261 / 3] {
            stack.frame = CGRect(origin: CGPoint(x: 0, y: origin), size: fittingSize)
            stack.setNeedsLayout()
            stack.layoutIfNeeded()
            let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
            let item = stack.collectionView(
                collection,
                layout: collection.collectionViewLayout,
                sizeForItemAt: IndexPath(item: 0, section: 0)
            )
            #expect(item.height < collection.bounds.height)
        }
    }

    @Test
    func `display scale changes invalidate rounded intrinsic height`() {
        let counter = MeasurementCounter()
        counter.height = 50.3
        let stack = makeStack(counter: counter)
        stack.traitOverrides.displayScale = 1

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 200))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(stack)
        stack.frame = CGRect(x: 0, y: 0, width: 402, height: 51)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        #expect(stack.fittingSize(forWidth: 402).height == 51)
        stack.traitOverrides.displayScale = 3
        stack.updateTraitsIfNeeded()
        #expect(abs(stack.fittingSize(forWidth: 402).height - 151 / 3) < 0.001)
    }

    @Test
    func `transitional collection height does not change measured content height`() throws {
        let stack = makeAspectRatioStack()
        let fittingSize = stack.fittingSize(forWidth: 210)
        stack.frame = CGRect(origin: .zero, size: fittingSize)
        stack.layoutIfNeeded()
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)

        for height: CGFloat in [100, 150, 80, 150] {
            collection.frame.size.height = height
            let item = stack.collectionView(
                collection,
                layout: collection.collectionViewLayout,
                sizeForItemAt: IndexPath(item: 0, section: 0)
            )
            #expect(item.height < height)
            #expect(abs(item.height - height) < 0.001)
            #expect(stack.fittingSize(forWidth: 210).height == 150)
        }
    }

    @Test
    func `swift UI fitting proposal does not overwrite live UI kit item size`() throws {
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
        #expect(proposedSize.height == 50)
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
        )
        .size
        .width == 248)

        let liveSizeAfterBoundsChange = stack.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: 0)
        )
        #expect(liveSizeAfterBoundsChange.width == 248)
    }

    @Test
    func `fractional minimum width reuses measurements for matching item widths`() throws {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter, layout: .minimumWidth(columnWidth: 100, rows: 2, columnFraction: 0.5))
        let cases: [(CGFloat, CGFloat)] = [(210, 100), (209, 199 / 1.5), (160, 100), (159, 159), (210, 100)]
        for (width, _) in cases {
            #expect(stack.fittingSize(forWidth: width).height == 110)
        }
        #expect(counter.value == 3)
        for (width, itemWidth) in cases {
            let size = stack.fittingSize(forWidth: width)
            #expect(size.height == 110)
            stack.bounds = CGRect(origin: .zero, size: size)
            stack.layoutSubviews()
            let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
            let attributes = try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            #expect(abs(attributes.size.width - itemWidth) < 0.001)
            #expect(abs(attributes.size.height - 50) < 0.001)
        }
    }

    @Test
    func `changing only the minimum width fraction invalidates sizing`() {
        let stack = makeStack(counter: MeasurementCounter(), layout: .minimumWidth(columnWidth: 100, rows: 1))
        #expect(stack.fittingSize(forWidth: 160).height == 50)
        stack.update(newData: [0], alignedLeadingElementID: nil, layout: .minimumWidth(columnWidth: 100, rows: 1, columnFraction: 0.5))
        #expect(stack.computeSizes(forWidth: 160).itemSize.width == 100)
    }

    @Test
    func `minimum width uses one column when the container is narrower than the minimum`() {
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
    func `invalid row count uses one row`() {
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
    func `large collection resize measures only one item per width`() {
        let counter = MeasurementCounter()
        let stack = makeStack(counter: counter, data: Array(0 ..< 10000))
        for step in 0 ..< 120 {
            let width = CGFloat(320 + step * 8)
            _ = stack.fittingSize(forWidth: width)
        }
        #expect(counter.value == 120, "Resizing must measure one representative item per width, regardless of the data count")
    }

    @Test
    func `insets and spacing update without changing container width`() throws {
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
    func `redraw uses updated content provider`() {
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
