#if os(iOS)
@testable import CollectionHStack
import SwiftUI

@MainActor
final class LibraryFixture {
    let state = LibraryFixtureState()
    let host: UIHostingController<AnyView>
    let window: UIWindow
    private var samples: [CGFloat] = []
    private var anchorItem = 0
    private var anchorDistance: CGFloat = 0

    init(itemCount: Int = 600) {
        host = UIHostingController(rootView: AnyView(LibraryFixtureRoot(state: state, itemCount: itemCount)))
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    deinit {
        MainActor.assumeIsolated { window.isHidden = true }
    }

    var collection: UICollectionView {
        findCollection(host.view)!
    }

    var visibleCellCount: Int {
        collection.visibleCells.count
    }

    func layOut(width: CGFloat) {
        window.frame.size.width = width
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    func scroll(toItem item: Int) {
        let collection = collection
        collection.layoutIfNeeded()
        let attributes = collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: item, section: 0))!
        // Preserve the leading column, including the row's horizontal inset.
        collection.setContentOffset(CGPoint(x: attributes.frame.minX - 20, y: 0), animated: false)
        collection.layoutIfNeeded()
        anchorItem = item
        anchorDistance = 20
    }

    /// Distance the anchored item moved relative to the leading edge.
    func sample() {
        let collection = collection
        collection.layoutIfNeeded()
        guard let attributes = collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: anchorItem, section: 0))
        else { return }

        samples.append(abs(attributes.frame.minX - collection.contentOffset.x - anchorDistance))
    }

    func visibleContentIsCurrent() -> Bool {
        let collection = collection
        collection.layoutIfNeeded()
        let width = collection.superview!.bounds.width
        return collection.indexPathsForVisibleItems.allSatisfy { path in
            guard let suppliedWidth = state.providedWidths[path.item] else { return false }

            return abs(suppliedWidth - width) <= 0.5
        }
    }

    private func findCollection(_ view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView {
            return collection
        }
        return view.subviews.lazy.compactMap(findCollection).first
    }

    private func record(frames: Int = 0, _ body: () async throws -> Void) async rethrows -> StackResizeReport {
        samples = []
        let suppliedViews = state.suppliedViews
        try await body()
        return StackResizeReport(
            drift: samples,
            frames: frames,
            suppliedViews: state.suppliedViews - suppliedViews
        )
    }

    /// Each width is one frame of a live window resize, laid out and committed synchronously.
    func recordLiveResize(widths: [CGFloat]) -> StackResizeReport {
        recordFrames(values: widths) { layOut(width: $0) }
    }

    func recordFrames(values: [CGFloat], apply: (CGFloat) -> Void) -> StackResizeReport {
        samples = []
        let suppliedViews = state.suppliedViews
        for value in values {
            apply(value)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            CATransaction.flush()
            sample()
        }
        return StackResizeReport(
            drift: samples,
            frames: values.count,
            suppliedViews: state.suppliedViews - suppliedViews
        )
    }

    /// Samples each snap frame, then lets it settle before the next.
    func recordSnaps(widths: [CGFloat]) async throws -> StackResizeReport {
        try await record(frames: widths.count) {
            for width in widths {
                layOut(width: width)
                CATransaction.flush()
                sample()
                try await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func recordAnimation(change: () -> Void) async throws -> StackResizeReport {
        try await record {
            change()
            for _ in 0 ..< 40 {
                try await Task.sleep(for: .milliseconds(12))
                sample()
            }
        }
    }
}

#endif
