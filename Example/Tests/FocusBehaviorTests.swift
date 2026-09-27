#if os(tvOS)
@testable import CollectionHStack
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct FocusBehaviorTests {
    @Test
    func scopePreservesTheSwiftUIEnvironment() async throws {
        var observedLocale: String?
        let controller = UIHostingController(rootView:
            CollectionHStackFocusScope {
                ScopeEnvironmentProbe { observedLocale = $0 }
            }
            .environment(\.locale, Locale(identifier: "fr_CA"))
        )
        let window = UIWindow()
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(200))
        #expect(observedLocale == "fr_CA")
    }

    @Test
    func explicitChildFocusIsNotOverridden() async throws {
        let harness = FocusHarness(initial: .leading, returning: .leading)
        defer { harness.close() }
        try await harness.start()
        try await harness.focusItem(2)
        #expect(harness.focusedIndex == 2)
        #expect(harness.focusEvents == [2])
    }

    @Test
    func leadingEntryPreservesNavigationAndReturnsToCurrentLeadingItem() async throws {
        let harness = FocusHarness(initial: .leading, returning: .leading)
        defer { harness.close() }
        try await harness.start()
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 0)
        #expect(harness.focusEvents == [0])
        try await harness.focusItem(2)
        #expect(harness.focusedIndex == 2)
        try await harness.leave()
        harness.view.scrollTo(index: 8, animated: false)
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 8)
        #expect(harness.focusEvents == [0, 2, 8])
        try await harness.leave()
        #expect(harness.focusedIndex == nil)
    }

    @Test
    func automaticEntryAndReturnKeepTheProposedItem() async throws {
        let harness = FocusHarness()
        defer { harness.close() }
        try await harness.start()
        try await harness.focusItem(2)
        #expect(harness.focusedIndex == 2)
        try await harness.leave()
        try await harness.focusItem(1)
        #expect(harness.focusedIndex == 1)
    }

    @Test(arguments: [CollectionHStackFocusBehavior.Initial.automatic, .leading])
    func returningRestoresLastItemEvenAfterScrollingAway(initial: CollectionHStackFocusBehavior.Initial) async throws {
        let harness = FocusHarness(initial: initial, returning: .lastFocused)
        defer { harness.close() }
        try await harness.start()
        if initial == .leading {
            try await harness.enterCollection()
        } else {
            try await harness.focusItem(2)
        }
        #expect(harness.focusedIndex == (initial == .leading ? 0 : 2))
        try await harness.focusItem(3)
        #expect(harness.focusedIndex == 3)
        try await harness.leave()
        harness.view.scrollTo(index: 12, animated: false)
        let beforeEntry = harness.focusEvents.count
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 3)
        #expect(Array(harness.focusEvents.dropFirst(beforeEntry)) == [3])
    }

    @Test
    func rememberedFocusFollowsIdentityThroughReordering() async throws {
        let harness = FocusHarness(returning: .lastFocused)
        defer { harness.close() }
        try await harness.start()
        try await harness.focusItem(2)
        try await harness.leave()
        var reordered = harness.configuration.data
        reordered.swapAt(2, 10)
        harness.update(data: reordered)
        try await harness.settle()
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 10)
        #expect(harness.focusEvents == [2, 10])
    }

    @Test(arguments: [false, true])
    func missingRememberedElementFallsBackToLeading(usePrefix: Bool) async throws {
        let harness = FocusHarness(returning: .lastFocused)
        defer { harness.close() }
        try await harness.start()
        try await harness.focusItem(3)
        try await harness.leave()
        if usePrefix {
            harness.configuration = harness.configuration.dataPrefix(3)
            harness.update(data: harness.configuration.data)
        } else {
            harness.update(data: harness.configuration.data.filter { $0 != 3 })
        }
        try await harness.settle()
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 0)
        #expect(harness.focusEvents == [3, 0])
    }

    @Test
    func runtimePolicyChangePreservesHistoryWithoutMovingCurrentFocus() async throws {
        let harness = FocusHarness()
        defer { harness.close() }
        try await harness.start()
        try await harness.focusItem(2)
        harness.configuration = harness.configuration.focusBehavior(initial: .leading, returning: .lastFocused)
        harness.view.configure(harness.configuration)
        try await harness.settle()
        #expect(harness.focusedIndex == 2)
        try await harness.leave()
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 2)
        #expect(harness.focusEvents == [2, 2])
    }

    @Test
    func leadingSkipsDisabledContent() async throws {
        let harness = FocusHarness(initial: .leading, disabledIDs: [0])
        defer { harness.close() }
        try await harness.start()
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 1)
        #expect(harness.focusEvents == [1])
    }

    @Test
    func leadingUsesInitialScrollPositionAndTopRow() async throws {
        let harness = FocusHarness(initial: .leading, rows: 2, initialID: 8)
        defer { harness.close() }
        try await harness.start()
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 8)
        #expect(harness.focusEvents == [8])
    }

    @Test
    func emptyCollectionCanReceiveDataBeforeItsFirstFocus() async throws {
        let harness = FocusHarness(initial: .leading, data: [])
        defer { harness.close() }
        try await harness.start()
        harness.update(data: Array(0 ..< 20))
        try await harness.settle()
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 0)
        #expect(harness.focusEvents == [0])
    }

    @Test
    func carouselRemembersTheFocusedOccurrence() async throws {
        let harness = FocusHarness(returning: .lastFocused, data: [0, 1, 2, 3], carousel: true)
        defer { harness.close() }
        try await harness.start()
        harness.view.scrollTo(index: 12, animated: false)
        try await harness.focusItem(14)
        try await harness.leave()
        harness.view.scrollTo(index: 0, animated: false)
        try await harness.enterCollection()
        #expect(harness.focusedIndex == 14)
        #expect(harness.focusEvents == [14, 14])
    }
}

@MainActor
private final class FocusHarness {
    typealias Configuration = CollectionHStack<Int, [Int], Int, FocusTestCard>
    let view: UICollectionHStack<Int, [Int], Int, FocusTestCard>
    var configuration: Configuration
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    let controller = FocusTestController()
    let outside = UIButton(type: .system)
    private(set) var focusEvents: [Int] = []

    var collection: FocusCollectionView {
        view.subviews.compactMap { $0 as? FocusCollectionView }.first!
    }

    init(
        initial: CollectionHStackFocusBehavior.Initial = .automatic,
        returning: CollectionHStackFocusBehavior.Returning = .automatic,
        rows: Int = 1,
        initialID: Int? = nil,
        data: [Int] = Array(0 ..< 20),
        disabledIDs: Set<Int> = [],
        carousel: Bool = false
    ) {
        var configuration = Configuration(uniqueElements: data, id: \.self, columns: 4, rows: rows) { id in
            FocusTestCard(id: id, disabled: disabledIDs.contains(id))
        }
        .insets(horizontal: 40).itemSpacing(20).scrollBehavior(.continuousLeadingEdge)
        .initialElement(id: initialID).focusBehavior(initial: initial, returning: returning)
        if carousel {
            configuration = configuration.asCarousel()
        }
        self.configuration = configuration
        view = .init(
            id: configuration.id, alignedLeadingElementID: nil, clipsToBounds: false,
            data: data, dataPrefix: nil, didScrollToItems: { _ in },
            insets: configuration.insets, isCarousel: configuration.isCarousel, itemSpacing: configuration.itemSpacing,
            layout: configuration.layout, onReachedLeadingEdge: {}, onReachedLeadingEdgeOffset: .offset(0),
            onReachedTrailingEdge: {}, onReachedTrailingEdgeOffset: .offset(0),
            onPrefetchingElements: { _ in }, onCancelPrefetchingElements: { _ in },
            proxy: configuration.proxy, scrollBehavior: configuration.scrollBehavior,
            initialElementID: configuration.initialElementID, viewProvider: configuration.viewProvider
        )
        view.configure(configuration)
        collection.contentInsetAdjustmentBehavior = .never
        window.rootViewController = controller
        controller.view.addSubview(outside)
        outside.setTitle("Outside the collection", for: .normal)
        outside.frame = CGRect(x: 100, y: 80, width: 400, height: 80)
        controller.view.addSubview(view)
        layout()
        controller.target = outside
        controller.onFocusChange = { [weak self] in
            if let self, let index = self.focusedIndex {
                self.focusEvents.append(index)
            }
        }
    }

    func start() async throws {
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.makeKeyAndVisible()
        controller.setNeedsFocusUpdate()
        controller.updateFocusIfNeeded()
        try await settle()
        if UIFocusSystem.focusSystem(for: outside)?.focusedItem == nil {
            controller.setNeedsFocusUpdate()
            controller.updateFocusIfNeeded()
            try await settle()
        }
        #expect(UIFocusSystem.focusSystem(for: outside)?.focusedItem === outside)
    }

    func focusItem(_ index: Int) async throws {
        collection.layoutIfNeeded()
        let cell = try #require(collection.cellForItem(at: IndexPath(item: index, section: 0)))
        // Explicit child requests must remain explicit, including when outside.
        controller.target = cell.contentView
        controller.setNeedsFocusUpdate()
        controller.updateFocusIfNeeded()
        try await settle()
    }

    func enterCollection() async throws {
        controller.target = collection
        controller.setNeedsFocusUpdate()
        controller.updateFocusIfNeeded()
        try await settle()
    }

    func leave() async throws {
        controller.target = outside
        controller.setNeedsFocusUpdate()
        controller.updateFocusIfNeeded()
        try await settle()
    }

    var focusedIndex: Int? {
        var environment: UIFocusEnvironment? = UIFocusSystem.focusSystem(for: collection)?.focusedItem
        while let current = environment {
            if let cell = current as? UICollectionViewCell, let path = collection.indexPath(for: cell) {
                return path.item
            }
            environment = current.parentFocusEnvironment
        }
        return nil
    }

    func update(data: [Int]) {
        let old = configuration
        configuration = Configuration(
            id: old.id, data: data, dataPrefix: old.dataPrefix, insets: old.insets,
            isCarousel: old.isCarousel, itemSpacing: old.itemSpacing, layout: old.layout,
            scrollBehavior: old.scrollBehavior, initialElementID: old.initialElementID,
            viewProvider: old.viewProvider
        ).focusBehavior(initial: old.focusBehavior.initial, returning: old.focusBehavior.returning)
        view.configure(configuration)
        view.update(newData: data, alignedLeadingElementID: nil, dataPrefix: configuration.dataPrefix, layout: configuration.layout)
        layout()
    }

    func layout() {
        view.frame = CGRect(x: 100, y: 300, width: 1500, height: view.fittingSize(forWidth: 1500).height)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    func close() {
        window.isHidden = true
    }
}

private final class FocusTestController: UIViewController {
    var target: UIView?
    var onFocusChange: (() -> Void)?
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        target.map { [$0] } ?? []
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        onFocusChange?()
    }
}

private struct FocusTestCard: View {
    let id: Int
    let disabled: Bool
    var body: some View {
        Button("Item \(id)") {}
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .disabled(disabled)
    }
}

private struct ScopeEnvironmentProbe: View {
    @Environment(\.locale) private var locale
    let observed: (String) -> Void

    var body: some View {
        Text("Environment probe")
            .onAppear { observed(locale.identifier) }
    }
}
#endif
