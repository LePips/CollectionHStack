#if os(tvOS)
import SwiftUI

/// A shared native focus environment for collections and the controls surrounding them.
///
/// Wrap the common parent of the collections and the controls that can enter them.
/// Include navigation containers here when focus can enter from their controls.
/// Directional entry is resolved before a hosted control receives focus. Explicit
/// programmatic requests to focus a particular child remain unchanged.
public struct CollectionHStackFocusScope<Content: View>: UIViewControllerRepresentable {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = CollectionFocusScopeController(rootView: AnyView(content.environment(\.self, context.environment)))
        // The surrounding SwiftUI layout has already accounted for safe areas.
        controller.safeAreaRegions = []
        controller.view.backgroundColor = nil
        return controller
    }

    public func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        controller.rootView = AnyView(content.environment(\.self, context.environment))
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiViewController: UIHostingController<AnyView>,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        // Scroll views leave their scrolling axis unspecified. Ask the hosted
        // content for its height instead of accepting UIKit's zero-height default.
        return uiViewController.sizeThatFits(in: CGSize(
            width: width,
            height: proposal.height ?? .greatestFiniteMagnitude
        ))
    }
}

private protocol CollectionFocusRouting: UIFocusEnvironment {}

final class CollectionFocusScopeController<Content: View>: UIHostingController<Content>, CollectionFocusRouting {
    private weak var pendingCollection: FocusCollectionView?
    private var requestGeneration = 0

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let pendingCollection {
            return pendingCollection.entryFocusEnvironments()
        }
        return super.preferredFocusEnvironments
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        requestGeneration += 1
        super.didUpdateFocus(in: context, with: coordinator)
    }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        guard super.shouldUpdateFocus(in: context) else { return false }
        guard !context.focusHeading.isEmpty,
              let previous = context.previouslyFocusedItem,
              contains(previous),
              let collection = collection(containing: context.nextFocusedItem),
              collection.indexPath(containing: previous) == nil,
              isNearestScope(to: collection, containing: previous),
              !collection.preferredEntryIdentities().isEmpty else { return true }

        // Reject the spatial candidate before its controls receive a focus update.
        // The shared ancestor can then resolve the collection's preferred entry.
        requestGeneration += 1
        let generation = requestGeneration
        DispatchQueue.main.async { [weak self, weak collection, weak previous] in
            guard let self, let collection, let previous,
                  self.requestGeneration == generation,
                  collection.window === self.view.window,
                  self.contains(collection),
                  let system = UIFocusSystem.focusSystem(for: self), system.focusedItem === previous else { return }
            self.pendingCollection = collection
            defer { self.pendingCollection = nil }
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
        }
        return false
    }

    private func contains(_ item: UIFocusEnvironment) -> Bool {
        var environment: UIFocusEnvironment? = item
        while let current = environment {
            if current === self {
                return true
            }
            environment = current.parentFocusEnvironment
        }
        return false
    }

    private func isNearestScope(to collection: FocusCollectionView, containing previous: UIFocusItem) -> Bool {
        var environment: UIFocusEnvironment? = collection
        while let current = environment, current !== self {
            if current is CollectionFocusRouting {
                var ancestor: UIFocusEnvironment? = previous
                while let candidate = ancestor {
                    if candidate === current {
                        return false
                    }
                    ancestor = candidate.parentFocusEnvironment
                }
            }
            environment = current.parentFocusEnvironment
        }
        return environment === self
    }

    private func collection(containing item: UIFocusItem?) -> FocusCollectionView? {
        var environment: UIFocusEnvironment? = item
        while let current = environment, current !== self {
            if let collection = current as? FocusCollectionView {
                return collection
            }
            environment = current.parentFocusEnvironment
        }
        return nil
    }
}
#endif
