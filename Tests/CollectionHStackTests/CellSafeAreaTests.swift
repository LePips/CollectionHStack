#if canImport(UIKit)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct CellSafeAreaTests {
    @Test
    func `cell content keeps its bounds when scrolling beneath bars`() async throws {
        let geometry = CellGeometry()
        let cell = HostingCollectionViewCell<CellContent>(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        cell.setup(view: CellContent(geometry: geometry), id: 1)
        let view = try #require(cell.contentView.subviews.first)
        let host = try #require(view.next as? UIHostingController<AnyView>)
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = parent
        parent.addChild(host)
        parent.view.addSubview(cell)
        host.didMove(toParent: parent)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for insets in [
            UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 84),
            UIEdgeInsets(top: 24, left: 84, bottom: 34, right: 0),
            .zero,
        ] {
            parent.additionalSafeAreaInsets = insets
            for id in [1, 2] {
                cell.setup(view: CellContent(geometry: geometry), id: id)
                parent.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
                #expect(geometry.size == cell.bounds.size)
                #expect(geometry.insets == .init())
                #expect(cell.contentView.subviews.first === view)
            }
        }
        #expect(host.safeAreaRegions.contains(.keyboard))
    }
}

@MainActor
private final class CellGeometry {
    var size: CGSize = .zero
    var insets: EdgeInsets = .init()
}

private struct CellContent: View {
    let geometry: CellGeometry

    var body: some View {
        GeometryReader { proxy in
            Color.blue.onGeometryChange(for: CGSize.self) { $0.size } action: {
                geometry.size = $0
                geometry.insets = proxy.safeAreaInsets
            }
        }
    }
}
#endif
