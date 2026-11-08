#if os(iOS) || os(tvOS)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct SafeAreaInsetsTests {
    @Test(arguments: [false, true])
    func `application insets remain aligned while owner safe area and width change`(clipsToBounds: Bool) throws {
        let configuration = CollectionHStack(
            uniqueElements: Array(0 ..< 100),
            layout: .grid(columns: 3, rows: 1, columnTrailingInset: 0)
        ) { _ in
            VStack(spacing: 8) {
                Color.blue.aspectRatio(2 / 3, contentMode: .fit)
                Text("Poster title").font(.system(size: 18)).lineLimit(1)
            }
        }
        .insets(horizontal: 60)
        .itemSpacing(20)
        .clipsToBounds(clipsToBounds)
        .scrollBehavior(.continuousLeadingEdge)
        .contentInsetAdjustmentBehavior(.never)
        let stack = makeStack(configuration)
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = controller
        controller.view.addSubview(stack)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)

        for ownerInset: CGFloat in [160, 240, 80] {
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: ownerInset, bottom: 0, right: 80)
            for reduction: CGFloat in [0, 0.1, 0.2, 120, 0] {
                let width = controller.view.bounds.width - 80 - reduction
                let fitted = stack.fittingSize(forWidth: width)
                stack.frame = CGRect(x: 40, y: 100, width: width, height: fitted.height)
                controller.view.layoutIfNeeded()
                stack.layoutIfNeeded()
                collection.layoutIfNeeded()

                #expect(controller.view.safeAreaInsets.left > 0)
                #expect(collection.safeAreaInsets.left > 0, "Exercise a native scroll view that would inherit the owner's safe area")
                #expect(collection.adjustedContentInset == .zero)
                let first = try #require(collection.cellForItem(at: IndexPath(item: 0, section: 0)))
                let frame = collection.convert(first.frame, to: stack)
                #expect(abs(frame.minX - 60) < 0.001, "Only the application's explicit inset belongs before its first poster")
                #expect(abs(frame.width - (width - 160) / 3) < 0.001)
                #expect(abs(frame.height - fitted.height) < 1)
                #expect(collection.visibleCells.count < 15)
            }
        }
    }

    @Test
    func `automatic remains the default and explicit native safe area policies survive updates`() throws {
        let configuration = CollectionHStack(count: 100, columns: 3, rows: 1) { _ in
            Color.blue.frame(height: 100)
        }
        .insets(horizontal: 60)
        .clipsToBounds(true)
        #expect(configuration.contentInsetAdjustmentBehavior == .automatic)
        let stack = makeStack(configuration)
        let controller = UIViewController()
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 80, bottom: 0, right: 40)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = controller
        controller.view.addSubview(stack)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collection = try #require(stack.subviews.compactMap { $0 as? UICollectionView }.first)
        let width = controller.view.bounds.width
        stack.frame = CGRect(x: 0, y: 100, width: width, height: stack.fittingSize(forWidth: width).height)

        func check(_ behavior: UIScrollView.ContentInsetAdjustmentBehavior) {
            controller.view.layoutIfNeeded()
            stack.layoutIfNeeded()
            collection.layoutIfNeeded()
            #expect(collection.contentInsetAdjustmentBehavior == behavior)
            #expect(collection.safeAreaInsets.left > 0)
            if behavior == .never {
                #expect(collection.adjustedContentInset == .zero)
            } else {
                #expect(collection.adjustedContentInset.left > 0, "Opting into UIKit safe areas must still have a visible effect")
                #expect(collection.adjustedContentInset.left == collection.safeAreaInsets.left)
            }
        }

        check(.automatic)
        for behavior: UIScrollView.ContentInsetAdjustmentBehavior in [.never, .always, .automatic, .never] {
            stack.configure(configuration.contentInsetAdjustmentBehavior(behavior))
            check(behavior)
        }
    }

    private func makeStack<Element, Data: Collection, ID: Hashable, Content: View>(
        _ configuration: CollectionHStack<Element, Data, ID, Content>
    ) -> UICollectionHStack<Element, Data, ID, Content> where Data.Element == Element, Data.Index == Int {
        let stack = UICollectionHStack(
            id: configuration.id, alignedLeadingElementID: nil, clipsToBounds: configuration.clipsToBounds,
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
        return stack
    }
}
#endif
