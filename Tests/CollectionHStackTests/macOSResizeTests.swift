#if os(macOS)
import AppKit
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct MacOSResizeTests {
    @Test(arguments: 0 ..< 4)
    func distantTargetStaysAnchoredAcrossRepeatedResizes(behaviorIndex: Int) async throws {
        let behavior: CollectionHStackScrollBehavior = [.continuous, .continuousLeadingEdge, .columnPaging, .fullPaging][behaviorIndex]
        let view = NSCollectionHStack(configuration: CollectionHStack(count: 10000, columns: 3, rows: 2) { _ in
            Color.blue.aspectRatio(2 / 3, contentMode: .fit)
        }.insets(horizontal: 20).itemSpacing(10).scrollBehavior(behavior))
        let window = present(view)
        defer { view.disconnect()
            window.close()
        }
        resize(view, window: window, width: 768)
        view.scrollTo(index: 9000, animated: false)

        for width: CGFloat in [320, 1366, 414, 1024, 768] {
            resize(view, window: window, width: width)
            try await Task.sleep(for: .milliseconds(160))
            view.layoutSubtreeIfNeeded()
            let frame = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 9000, section: 0))).frame
            let expected: CGFloat = switch behavior {
            case .continuousLeadingEdge, .columnPaging: frame.minX - 20
            case .continuous, .fullPaging: frame.midX - view.scrollView.contentSize.width / 2
            }
            #expect(abs(view.scrollView.contentView.bounds.minX - expected) < 0.5)
            #expect(view.collectionView.indexPathsForVisibleItems().contains(IndexPath(item: 9000, section: 0)))
            #expect(view.collectionView.visibleItems().count < 30)
        }
    }

    @Test
    func partiallyVisibleItemRetainsItsFractionAfterResize() throws {
        let view = NSCollectionHStack(configuration: CollectionHStack(count: 1000, columns: 3) { _ in
            Color.blue.frame(height: 40)
        }.insets(horizontal: 20).itemSpacing(10).scrollBehavior(.continuousLeadingEdge))
        let window = present(view)
        defer { view.disconnect()
            window.close()
        }
        resize(view, window: window, width: 768)
        let original = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 700, section: 0))).frame
        view.scrollView.contentView.scroll(to: CGPoint(x: original.minX + original.width * 0.3 - 20, y: 0))
        for width: CGFloat in [320, 1024, 768] {
            resize(view, window: window, width: width)
            let frame = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 700, section: 0))).frame
            #expect(abs(view.scrollView.contentView.bounds.minX - (frame.minX + frame.width * 0.3 - 20)) < 0.5)
        }
    }

    @Test(arguments: [false, true])
    func contentEdgesStayPinned(trailing: Bool) {
        let view = NSCollectionHStack(configuration: CollectionHStack(count: 12, columns: 3) { _ in
            Color.blue.frame(height: 40)
        }.insets(horizontal: 20).itemSpacing(10))
        let window = present(view)
        defer { view.disconnect()
            window.close()
        }
        resize(view, window: window, width: 320)
        view.scrollTo(index: trailing ? 11 : 0, animated: false)
        for width: CGFloat in [1366, 414, 1024, 320] {
            resize(view, window: window, width: width)
            let expected = trailing ? max(0, view.collectionLayout.collectionViewContentSize.width - view.scrollView.contentSize.width) : 0
            #expect(abs(view.scrollView.contentView.bounds.minX - expected) < 0.5)
        }
    }

    @Test(arguments: 0 ..< 3)
    func sizingVariantsKeepTheirLeadingItem(layoutIndex: Int) throws {
        let layout: CollectionHStackLayout = [
            .minimumWidth(columnWidth: 100, rows: 2),
            .selfSizingSameSize(rows: 2),
            .selfSizingVariadicWidth(rows: 2),
        ][layoutIndex]
        let view = NSCollectionHStack(configuration: CollectionHStack(uniqueElements: Array(0 ..< 1000), layout: layout) {
            Color.blue.frame(width: CGFloat(100 + ($0 % 4) * 20), height: 40)
        }.insets(horizontal: 20).itemSpacing(10).scrollBehavior(.continuousLeadingEdge))
        let window = present(view)
        defer { view.disconnect()
            window.close()
        }
        resize(view, window: window, width: 768)
        view.scrollTo(index: 700, animated: false)
        for width: CGFloat in [320, 1366, 768] {
            resize(view, window: window, width: width)
            let frame = try #require(view.collectionLayout.layoutAttributesForItem(at: IndexPath(item: 700, section: 0))).frame
            #expect(abs(view.scrollView.contentView.bounds.minX - (frame.minX - 20)) < 0.5)
        }
    }

    @Test
    func swiftUIResizeKeepsAlignedBindingAndInitialTarget() async throws {
        var aligned: Int?
        let configuration = CollectionHStack(count: 1000, columns: 3, rows: 2) { _ in
            Color.blue.aspectRatio(2, contentMode: .fit)
        }.insets(horizontal: 20).itemSpacing(10).scrollBehavior(.continuousLeadingEdge)
            .initialElement(id: 700)
            .alignedLeadingElement(id: Binding(get: { aligned }, set: { aligned = $0 }))
        let host = NSHostingView(rootView: VStack {
            configuration
            Spacer(minLength: 0)
        })
        let window = present(host)
        defer { window.close() }
        for width: CGFloat in [768, 320, 1366, 414] {
            window.setContentSize(CGSize(width: width, height: 500))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            #expect(aligned == 700)
            let collection = try #require(findCollection(host))
            #expect(collection.indexPathsForVisibleItems().contains(IndexPath(item: 700, section: 0)))
        }
    }

    private func findCollection(_ view: NSView) -> NSCollectionView? {
        if let collection = view as? NSCollectionView {
            return collection
        }
        return view.subviews.lazy.compactMap(findCollection).first
    }

    private func present(_ view: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 768, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        return window
    }

    private func resize(_ view: NSCollectionHStack<some Any, some Any, some Any, some Any>, window: NSWindow, width: CGFloat) {
        let size = CGSize(width: width, height: view.fittingSize(forWidth: width).height)
        window.setContentSize(size)
        view.frame = CGRect(origin: .zero, size: size)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }
}
#endif
