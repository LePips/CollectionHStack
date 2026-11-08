import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct EnvironmentSizingTests {
    @Test
    func `inherited typography updates measured and displayed poster height`() async throws {
        let fixture = EnvironmentPosterHost()
        defer { fixture.close() }
        var heights: [CGFloat] = []
        for (font, dynamicType): (Font, DynamicTypeSize) in [
            (.system(size: 12), .large),
            (.system(size: 32), .large),
            (.body, .accessibility3),
            (.system(size: 12), .large),
        ] {
            fixture.update(font: font, dynamicType: dynamicType)
            try await Task.sleep(for: .milliseconds(200))
            fixture.layout()
            let size = try fixture.itemSize()
            let expected = fixture.expectedSize(width: size.width, font: font, dynamicType: dynamicType)
            #expect(
                abs(size.height - expected.height) <= 1,
                "Allocated \(size.height), inherited typography requires \(expected.height)"
            )
            heights.append(size.height)
        }
        #expect(heights[1] > heights[0] + 20)
        #expect(abs(heights[0] - heights[3]) < 1)
    }
}

private struct EnvironmentPoster: View {
    var body: some View {
        VStack(spacing: 6) {
            Color.blue.aspectRatio(2 / 3, contentMode: .fit)
            Text("A title which can wrap onto multiple lines").lineLimit(3)
        }
    }
}

private struct EnvironmentPosterRoot: View {
    var font: Font = .system(size: 12)
    var dynamicType: DynamicTypeSize = .large

    var body: some View {
        let collection = CollectionHStack(count: 1000, columns: 3) { _ in EnvironmentPoster() }
        VStack(spacing: 0) {
            #if canImport(UIKit)
            collection.contentInsetAdjustmentBehavior(.never)
            #else
            collection
            #endif
            Spacer(minLength: 0)
        }
        .font(font)
        .dynamicTypeSize(dynamicType)
        .ignoresSafeArea()
    }
}

@MainActor
private final class EnvironmentPosterHost {
    #if os(macOS)
    let host: NSHostingView<EnvironmentPosterRoot>
    let window: NSWindow

    init() {
        _ = NSApplication.shared
        host = NSHostingView(rootView: EnvironmentPosterRoot())
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 900),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
    }

    func close() {
        window.close()
    }

    func layout() {
        host.layoutSubtreeIfNeeded()
    }

    func itemSize() throws -> CGSize {
        let collection = try #require(findCollection(host))
        return try #require(collection.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).size
    }

    func expectedSize(width: CGFloat, font: Font, dynamicType: DynamicTypeSize) -> CGSize {
        NSHostingView(rootView: EnvironmentPoster()
            .font(font)
            .dynamicTypeSize(dynamicType)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)).fittingSize
    }

    private func findCollection(_ view: NSView) -> NSCollectionView? {
        (view as? NSCollectionView) ?? view.subviews.lazy.compactMap(findCollection).first
    }
    #else
    let host: UIHostingController<EnvironmentPosterRoot>
    let window: UIWindow

    init() {
        host = UIHostingController(rootView: EnvironmentPosterRoot())
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    func close() {
        window.isHidden = true
    }

    func layout() {
        host.view.layoutIfNeeded()
    }

    func itemSize() throws -> CGSize {
        let collection = try #require(findCollection(host.view))
        return try #require(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).size
    }

    func expectedSize(width: CGFloat, font: Font, dynamicType: DynamicTypeSize) -> CGSize {
        UIHostingController(rootView: EnvironmentPoster()
            .font(font)
            .dynamicTypeSize(dynamicType)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true))
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private func findCollection(_ view: UIView) -> UICollectionView? {
        (view as? UICollectionView) ?? view.subviews.lazy.compactMap(findCollection).first
    }
    #endif

    func update(font: Font, dynamicType: DynamicTypeSize) {
        host.rootView = EnvironmentPosterRoot(font: font, dynamicType: dynamicType)
        layout()
    }
}
