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
        let host = try #require(view.next as? UIHostingController<CollectionItemContent<CellContent>>)
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
        // The collection adjusts its viewport for the keyboard. Nested item hosts
        // must not perform a second avoidance calculation inside individual cells.
        #expect(host.safeAreaRegions.isEmpty)
    }

    @Test
    func `unparented poster host keeps its geometry when partly outside the window`() async throws {
        let cell = HostingCollectionViewCell<ClippedPoster>(frame: CGRect(x: 0, y: 0, width: 160, height: 276))
        cell.setup(view: ClippedPoster(), id: 1)
        let hostedView = try #require(cell.contentView.subviews.first)
        let host = try #require(hostedView.next as? UIHostingController<CollectionItemContent<ClippedPoster>>)
        let parent = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.rootViewController = parent
        parent.view.addSubview(cell)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        #expect(host.parent == nil, "Match the reusable collection cell's native containment")

        for y: CGFloat in [0, 510, 30, 590, 140] {
            cell.frame.origin.y = y
            parent.view.setNeedsLayout()
            parent.view.layoutIfNeeded()
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            let marker = try #require(artworkMarker(in: cell))
            let artwork = marker.convert(marker.bounds, to: cell)
            #expect(abs(artwork.minX) < 0.5)
            #expect(abs(artwork.minY) < 0.5, "Partially visible artwork must not shift as if avoiding a keyboard")
            #expect(abs(artwork.width - 160) < 0.5)
            #expect(abs(artwork.height - 240) < 0.5)
            #expect(cell.contentView.subviews.first === hostedView)
        }
    }

    private func artworkMarker(in view: UIView) -> ArtworkMarkerView? {
        (view as? ArtworkMarkerView) ?? view.subviews.lazy.compactMap(artworkMarker).first
    }
}

private struct ClippedPoster: View {
    var body: some View {
        VStack(spacing: 8) {
            Color.blue
                .aspectRatio(2 / 3, contentMode: .fill)
                .background(ArtworkMarker())
            Text("Poster title").font(.system(size: 12)).frame(height: 28)
        }
    }
}

private final class ArtworkMarkerView: UIView {}

private struct ArtworkMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> ArtworkMarkerView {
        ArtworkMarkerView()
    }

    func updateUIView(_ uiView: ArtworkMarkerView, context: Context) {}
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
