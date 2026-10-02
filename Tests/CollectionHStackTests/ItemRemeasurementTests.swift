@testable import CollectionHStack
import Combine
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct ItemRemeasurementTests {

    @Test
    func titleToggleRemeasuresUsingTheLatestViewAndPreservesTheCollection() async throws {
        let model = RemeasurementModel()
        let fixture = RemeasurementFixture(model: model)
        let host = HostedRemeasurement(fixture)
        defer {
            host.close()
        }
        try await host.settle()
        let collection = try #require(host.collection)
        let originalHeight = try host.itemSize().height
        let originalStackHeight = host.stackHeight

        model.showsTitle = true
        for value in 0 ..< 10 {
            model.trigger.send(value)
        }
        try await host.settle()
        #expect(host.collection === collection)
        let titledHeight = try host.itemSize().height
        #expect(titledHeight > originalHeight + 10)
        #expect(abs(host.stackHeight - originalStackHeight - 2 * (titledHeight - originalHeight)) < 1)

        model.showsTitle = false
        model.trigger.send(10)
        try await host.settle()
        #expect(try abs(host.itemSize().height - originalHeight) < 1)
        #expect(abs(host.stackHeight - originalStackHeight) < 1)
    }

    @Test
    func currentValuePublisherSettlesAndChangingTheSourceCancelsTheOldSubscription() async throws {
        let model = RemeasurementModel()
        let host = HostedRemeasurement(RemeasurementFixture(model: model, currentValue: true))
        defer {
            host.close()
        }
        try await host.settle()
        #expect(model.primarySubscriptions == 1)
        let settledMeasurements = model.contentRequests
        try await host.settle()
        #expect(model.contentRequests == settledMeasurements, "The initial value must not cause resubscription")

        model.current.send(1)
        try await host.settle()
        #expect(model.contentRequests > settledMeasurements)
        let remeasuredContentRequests = model.contentRequests
        try await host.settle()
        #expect(model.contentRequests == remeasuredContentRequests)

        model.useAlternate = true
        try await host.settle()
        #expect(model.primarySubscriptions == 0)
        #expect(model.alternateSubscriptions == 1)

        let unchangedMeasurements = model.contentRequests
        model.current.send(1)
        try await host.settle()
        #expect(model.contentRequests == unchangedMeasurements)

        model.showsTitle = true
        model.alternate.send(1)
        try await host.settle()
        #expect(model.contentRequests > unchangedMeasurements)
    }

    @Test
    func oneShotPublisherSettlesAfterItsInitialInvalidation() async throws {
        let model = RemeasurementModel()
        let host = HostedRemeasurement(
            CollectionHStack(count: 4, columns: 2) { _ in
                model.contentRequests += 1
                return Color.blue
                    .frame(height: 50)
            }
            .remeasureItems(on: Just(()))
        )
        defer {
            host.close()
        }
        try await host.settle()
        #expect(model.contentRequests > 0)
        let settledMeasurements = model.contentRequests
        try await host.settle()
        #expect(model.contentRequests == settledMeasurements)
    }
}

private final class RemeasurementModel: ObservableObject {

    @Published
    var showsTitle = false

    @Published
    var useAlternate = false

    let trigger = PassthroughSubject<Int, Never>()
    let current = CurrentValueSubject<Int, Never>(0)
    let alternate = CurrentValueSubject<Int, Never>(0)
    var contentRequests = 0
    var primarySubscriptions = 0
    var alternateSubscriptions = 0
}

private struct RemeasurementFixture: View {

    @ObservedObject
    var model: RemeasurementModel

    var currentValue = false

    private var publisher: AnyPublisher<Int, Never> {
        guard currentValue else {
            return model.trigger.eraseToAnyPublisher()
        }
        let alternate = model.useAlternate
        return (alternate ? model.alternate : model.current)
            .handleEvents(
                receiveSubscription: { _ in
                    if alternate {
                        model.alternateSubscriptions += 1
                    } else {
                        model.primarySubscriptions += 1
                    }
                },
                receiveCancel: {
                    if alternate {
                        model.alternateSubscriptions -= 1
                    } else {
                        model.primarySubscriptions -= 1
                    }
                }
            )
            .eraseToAnyPublisher()
    }

    var body: some View {
        let showsTitle = model.showsTitle
        VStack(spacing: 0) {
            CollectionHStack(count: 1000, columns: 2, rows: 2) { _ in
                model.contentRequests += 1
                return VStack(spacing: 4) {
                    Rectangle()
                        .fill(.blue)
                        .aspectRatio(2, contentMode: .fit)

                    if showsTitle {
                        Text("One line title")
                            .font(.system(size: 14))
                            .lineLimit(1)
                    }
                }
            }
            .insets(horizontal: 0)
            .itemSpacing(10)
            .remeasureItems(on: publisher)
            Spacer(minLength: 0)
        }
    }
}

@MainActor
private final class HostedRemeasurement<Content: View> {

    #if os(macOS)
    private let host: NSHostingView<Content>
    private let window: NSWindow
    var collection: NSCollectionView? {
        findCollection(host)
    }

    var stackHeight: CGFloat {
        collection?.enclosingScrollView?.bounds.height ?? 0
    }

    init(_ content: Content) {
        _ = NSApplication.shared
        host = NSHostingView(rootView: content)
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 410, height: 800),
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

    private func layout() {
        host.layoutSubtreeIfNeeded()
    }

    private func findCollection(_ view: NSView) -> NSCollectionView? {
        (view as? NSCollectionView) ?? view.subviews.lazy.compactMap(findCollection).first
    }

    func itemSize() throws -> CGSize {
        try #require(collection?.collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).size
    }
    #else
    private let host: UIHostingController<Content>
    private let window: UIWindow
    var collection: UICollectionView? {
        findCollection(host.view)
    }

    var stackHeight: CGFloat {
        collection?.bounds.height ?? 0
    }

    init(_ content: Content) {
        host = UIHostingController(rootView: content)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 410, height: 800))
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    func close() {
        window.isHidden = true
    }

    private func layout() {
        host.view.layoutIfNeeded()
    }

    private func findCollection(_ view: UIView) -> UICollectionView? {
        (view as? UICollectionView) ?? view.subviews.lazy.compactMap(findCollection).first
    }

    func itemSize() throws -> CGSize {
        try #require(collection?.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))).size
    }
    #endif

    func settle() async throws {
        layout()
        try await Task.sleep(for: .milliseconds(180))
        layout()
    }
}
