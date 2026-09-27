#if os(tvOS)
import CollectionHStack
import SwiftUI

/// Enabled only by the UI test launch argument. Records every native focus commit,
/// including any intermediate item that an eventual-focus assertion would miss.
@MainActor
final class FocusExampleProbe: ObservableObject {
    let enabled = ProcessInfo.processInfo.arguments.contains("--focus-probe")
    @Published private(set) var events: [String] = []
    private var observer: NSObjectProtocol?

    init() {
        guard enabled else { return }
        observer = NotificationCenter.default
            .addObserver(forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
                    else { return }
                    self?.record(context.nextFocusedItem)
                }
            }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func record(_ item: UIFocusItem?) {
        var environment: UIFocusEnvironment? = item
        var cell: UICollectionViewCell?
        while let current = environment {
            if let candidate = current as? UICollectionViewCell {
                cell = candidate
            }
            if let collection = current as? UICollectionView,
               collection.superview is any _UICollectionHStack,
               let cell, let path = collection.indexPath(for: cell), let window = collection.window
            {
                let collections = collections(in: window)
                    .sorted { $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY }
                if let row = collections.firstIndex(where: { $0 === collection }) {
                    events.append("row\(row)-item\(path.item)")
                }
                return
            }
            environment = current.parentFocusEnvironment
        }
    }

    private func collections(in view: UIView) -> [UICollectionView] {
        if let collection = view as? UICollectionView, collection.superview is any _UICollectionHStack {
            return [collection]
        }
        return view.subviews.flatMap { collections(in: $0) }
    }
}
#endif
