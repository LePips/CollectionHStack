#if os(tvOS)
import CollectionHStack
import Observation
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct FocusScopeSizingTests {
    @Test
    func localScopePreservesSectionLayoutAsWidthAndContentChange() async throws {
        var measurements: [[CGSize]] = []
        for scoped in [false, true] {
            let model = ScopeSizeModel()
            let host = UIHostingController(rootView: ScopeSizeFixture(scoped: scoped, model: model))
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let parent = UIViewController()
            window.rootViewController = parent
            window.makeKeyAndVisible()
            parent.addChild(host)
            parent.view.addSubview(host.view)
            host.didMove(toParent: parent)
            defer { window.isHidden = true }
            var sizes: [CGSize] = []
            for (width, metadataHeight): (CGFloat, CGFloat) in [(1920, 120), (1280, 120), (1280, 240), (1920, 160)] {
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 1080)
                model.metadataHeight = metadataHeight
                parent.view.setNeedsLayout()
                parent.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(250))
                #expect(model.sectionSize.height > 300)
                #expect(abs(model.sectionSize.width - width) < 1)
                sizes.append(model.sectionSize)
            }
            measurements.append(sizes)
        }
        for (original, scoped) in zip(measurements[0], measurements[1]) {
            #expect(abs(original.width - scoped.width) < 1)
            #expect(abs(original.height - scoped.height) < 1)
        }
    }
}

@Observable
@MainActor
private final class ScopeSizeModel {
    var metadataHeight: CGFloat = 120
    @ObservationIgnored var sectionSize: CGSize = .zero
}

private struct ScopeSizeFixture: View {
    let scoped: Bool
    let model: ScopeSizeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Color.gray.frame(height: 100)
                group.onGeometryChange(for: CGSize.self) { $0.size } action: { model.sectionSize = $0 }
                Color.green.frame(height: 100)
            }
        }.ignoresSafeArea()
    }

    @ViewBuilder private var group: some View {
        if scoped {
            CollectionHStackFocusScope { section }
        } else {
            section
        }
    }

    private var section: some View {
        let metadataHeight = model.metadataHeight
        return VStack(alignment: .leading, spacing: 30) {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(0 ..< 5) { season in Button("Season \(season)") {} }
                }.padding(.horizontal, 60)
            }.scrollClipDisabled().focusSection()
            CollectionHStack(uniqueElements: Array(0 ..< 20), layout: .grid(columns: 3.5, rows: 1, columnTrailingInset: 0)) { index in
                VStack(alignment: .leading) {
                    Button {} label: { Color.blue.aspectRatio(16.0 / 9.0, contentMode: .fit) }.buttonStyle(.card)
                    Button {} label: {
                        Text("Episode \(index)").frame(maxWidth: .infinity, alignment: .leading).frame(height: metadataHeight)
                    }
                }.focusSection().ignoresSafeArea()
            }
            .focusBehavior(initial: .leading, returning: .leading)
            .initialElement(id: 4)
            .clipsToBounds(false)
            .insets(horizontal: 60)
            .itemSpacing(40)
            .scrollBehavior(.continuousLeadingEdge)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
