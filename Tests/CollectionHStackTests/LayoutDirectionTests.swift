@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct LayoutDirectionTests {
    @Test(arguments: [(1, nil), (21, nil), (21, -1), (21, 6)] as [(Int, Int?)])
    func `hosted row mirrors its viewport`(count: Int, initialID: Int?) async throws {
        let proxy = CollectionHStackProxy()
        var alignedID: Int?
        var reached: [Edge] = []
        let ids = Array(0 ..< count)
        let row = CollectionHStack(uniqueElements: ids, id: \.self, columns: 3) { _ in
            Color.blue.frame(height: 40)
        }
        .proxy(proxy)
        .scrollBehavior(.columnPaging)
        .alignedLeadingElement(id: Binding(get: { alignedID }, set: { alignedID = $0 }))
        .insets(.init(top: 0, leading: 24, bottom: 0, trailing: 8))
        .clipsToBounds(true)
        .onReachedLeadingEdge(offset: .offset(1)) { reached.append(.leading) }
        .onReachedTrailingEdge(offset: .offset(1)) { reached.append(.trailing) }
        // An absent initial ID must still open at the leading edge.
        .initialElement(id: initialID)
        func root(_ direction: LayoutDirection, width: CGFloat = 320) -> some View {
            row.frame(width: width).environment(\.layoutDirection, direction)
        }

        #if canImport(UIKit)
        let host = UIHostingController(rootView: root(.rightToLeft))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 480, height: 200))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func frame(_ index: Int) throws -> CGRect {
            let view = try #require(proxy.collectionView)
            let collection = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
            let cell = try #require(collection.cellForItem(at: IndexPath(item: index, section: 0)))
            let viewport = view.convert(view.bounds, to: window)
            return cell.convert(cell.bounds, to: window).offsetBy(dx: -viewport.minX, dy: 0)
        }
        #else
        let host = NSHostingController(rootView: root(.rightToLeft))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 480, height: 200))
        window.orderBack(nil)
        defer { window.close() }
        func frame(_ index: Int) throws -> CGRect {
            let view = try #require(proxy.collectionView as? NSView)
            let scroll = try #require(view.subviews.compactMap { $0 as? NSScrollView }.first)
            let collection = try #require(scroll.documentView as? NSCollectionView)
            let item = try #require(collection.item(at: IndexPath(item: index, section: 0)))
            let viewport = view.convert(view.bounds, to: nil)
            return item.view.convert(item.view.bounds, to: nil).offsetBy(dx: -viewport.minX, dy: 0)
        }
        #endif

        try await Task.sleep(for: .milliseconds(250))
        let start = initialID.flatMap { ids.firstIndex(of: $0) } ?? 0
        #expect(try abs(frame(start).maxX - 296) <= 1)
        #expect(alignedID == start)
        let target = count == 1 ? 0 : 9
        proxy.scrollTo(id: target, animated: false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try abs(frame(target).maxX - 296) <= 1)
        #expect(alignedID == target)

        host.rootView = root(.rightToLeft, width: 380)
        try await Task.sleep(for: .milliseconds(250))
        #expect(try abs(frame(target).maxX - 356) <= 1)
        if count > 1 {
            reached.removeAll()
            proxy.scrollTo(index: count - 1, animated: false)
            try await Task.sleep(for: .milliseconds(200))
            #expect(try abs(frame(count - 1).minX - 8) <= 1)
            #expect(reached == [.trailing])
            proxy.scrollTo(index: 0, animated: false)
            try await Task.sleep(for: .milliseconds(200))
            #expect(reached == [.trailing, .leading])
            proxy.scrollTo(index: target, animated: false)
            try await Task.sleep(for: .milliseconds(200))
        }

        host.rootView = root(.leftToRight, width: 380)
        try await Task.sleep(for: .milliseconds(250))
        #expect(try abs(frame(target).minX - 24) <= 1)
    }
}
