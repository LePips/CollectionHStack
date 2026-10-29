#if os(iOS)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct SidebarResizeTests {
    @Test(arguments: [120.0, 300.0], [false, true])
    func `sidebar resizing updates cards without replacing retained cells`(minimumWidth: CGFloat, usesLayoutProposals: Bool) throws {
        for clipsToBounds in [false, true] {
            try verifySidebarResize(minimumWidth: minimumWidth, usesLayoutProposals: usesLayoutProposals, clipsToBounds: clipsToBounds)
        }
    }

    private func verifySidebarResize(minimumWidth: CGFloat, usesLayoutProposals: Bool, clipsToBounds: Bool) throws {
        var contentRequests = 0
        let configuration = CollectionHStack(
            uniqueElements: Array(0 ..< 200),
            layout: .minimumWidth(columnWidth: minimumWidth, rows: 1, columnFraction: 0.5)
        ) { _ in
            contentRequests += 1
            return VStack {
                Color.blue.aspectRatio(16 / 9, contentMode: .fit)
                Text("Poster title").lineLimit(1)
            }
        }
        .insets(horizontal: 24)
        .itemSpacing(10)
        .scrollBehavior(.continuousLeadingEdge)
        .clipsToBounds(clipsToBounds)
        .contentInsetAdjustmentBehavior(.never)

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
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = controller
        controller.view.addSubview(stack)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        let metrics = LayoutMetrics(layout: configuration.layout, insets: configuration.insets, itemSpacing: 10)
        let widths: [CGFloat] = [1180, 1179.5, 1150, 1100, 1053, 1027, 974, 945, 920, 888, 860.5, 860]

        func layOut(width: CGFloat) throws -> UICollectionViewCell {
            // The outer view owns the animated sidebar padding. UIKit must not
            // add its changing horizontal safe area again inside the row.
            controller.additionalSafeAreaInsets.left = 320
            let fitted = usesLayoutProposals ? stack.fittingSize(forProposedWidth: width) : stack.fittingSize(forWidth: width)
            stack.frame = CGRect(x: 1180 - width, y: 100, width: width, height: fitted.height)
            controller.view.layoutIfNeeded()
            stack.layoutIfNeeded()
            collection.layoutIfNeeded()

            let first = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
            #expect(abs(first.frame.height - fitted.height) < 1)
            #expect(abs(collection.convert(first.frame, to: stack).minX - 24) < 0.5)
            #expect(collection.adjustedContentInset.left == 0)
            #expect(collection.visibleCells.count < 30)
            return first
        }

        let retainedCell = try layOut(width: 1180)
        for steps in [widths, Array(widths.reversed())] {
            let sourceWidth = try #require(steps.first)
            let targetWidth = try #require(steps.last)
            let sourceItemWidth = try #require(metrics.itemWidth(for: sourceWidth))
            let targetItemWidth = try #require(metrics.itemWidth(for: targetWidth))
            let sourceItemHeight = retainedCell.frame.height
            if usesLayoutProposals {
                stack.prepareForLayout()
                _ = stack.fittingSize(forProposedWidth: targetWidth)
                let requestsBefore = contentRequests
                for width in steps {
                    _ = stack.fittingSize(forProposedWidth: width)
                }
                #expect(contentRequests - requestsBefore <= 1, "Only the destination needs a new content measurement")
            }
            let targetItemHeight = stack.computeSizes(forWidth: targetWidth).itemSize.height
            for width in steps {
                let first = try layOut(width: width)
                let progress = (width - sourceWidth) / (targetWidth - sourceWidth)
                let expectedWidth = usesLayoutProposals
                    ? sourceItemWidth + (targetItemWidth - sourceItemWidth) * progress
                    : try #require(metrics.itemWidth(for: width))
                #expect(abs(first.frame.width - expectedWidth) < 0.001)
                if usesLayoutProposals {
                    let expectedHeight = sourceItemHeight + (targetItemHeight - sourceItemHeight) * progress
                    #expect(abs(first.frame.height - expectedHeight) < 1)
                }
                #expect(first === retainedCell)
            }

            if usesLayoutProposals {
                // UIView bounds have reached the destination after pixel rounding,
                // but SwiftUI continues probing subpixel spring values afterward.
                let requestsBefore = contentRequests
                let direction: CGFloat = sourceWidth < targetWidth ? -1 : 1
                for remainder: CGFloat in [0.2, 0.1, 0.05, 0.01, 0.001, 0.0001] {
                    _ = stack.fittingSize(forProposedWidth: targetWidth + direction * remainder)
                }
                #expect(contentRequests == requestsBefore, "The spring tail must reuse its measured destination")
                #expect(retainedCell.frame.width == targetItemWidth)
            }
        }

        // Reversing before reaching the destination starts from the current card
        // size, not from either completed sidebar layout.
        if usesLayoutProposals {
            stack.prepareForLayout()
            _ = stack.fittingSize(forProposedWidth: 860)
            let interrupted = try layOut(width: 1027)
            let interruptedWidth = interrupted.frame.width
            stack.prepareForLayout()
            _ = stack.fittingSize(forProposedWidth: 1180)
            // A reversing spring retains velocity and can move beyond its source.
            let overshot = try layOut(width: 1000)
            let targetItemWidth = try #require(metrics.itemWidth(for: 1180))
            let overshotWidth = interruptedWidth + (targetItemWidth - interruptedWidth) * (1000 - 1027) / (1180 - 1027)
            #expect(abs(overshot.frame.width - overshotWidth) < 0.001)
            #expect(overshot === retainedCell)
            let resumed = try layOut(width: 1100)
            let expectedWidth = interruptedWidth + (targetItemWidth - interruptedWidth) * (1100 - 1027) / (1180 - 1027)
            #expect(abs(resumed.frame.width - expectedWidth) < 0.001)
            #expect(resumed === retainedCell)

            // A fresh update can shorten the destination without changing direction.
            let resumedWidth = resumed.frame.width
            stack.prepareForLayout()
            _ = stack.fittingSize(forProposedWidth: 1150)
            let shortened = try layOut(width: 1125)
            let shortenedTarget = try #require(metrics.itemWidth(for: 1150))
            #expect(abs(shortened.frame.width - (resumedWidth + shortenedTarget) / 2) < 0.001)

            // Cancelling an animation with an immediate layout must use native metrics.
            stack.prepareForLayout()
            _ = stack.fittingSize(forProposedWidth: 1140)
            let immediate = try layOut(width: 1140)
            let immediateWidth = try #require(metrics.itemWidth(for: 1140))
            #expect(abs(immediate.frame.width - immediateWidth) < 0.001)
        }

        stack.configure(configuration.contentInsetAdjustmentBehavior(.automatic))
        #expect(collection.contentInsetAdjustmentBehavior == .automatic)
        stack.configure(configuration)
        #expect(collection.contentInsetAdjustmentBehavior == .never)
    }
}
#endif
