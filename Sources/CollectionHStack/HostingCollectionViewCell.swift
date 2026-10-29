#if canImport(UIKit)
import SwiftUI

final class HostingCollectionViewCell<Content: View>: UICollectionViewCell {
    private var hostingController: UIHostingController<AnyView>?
    /// The collection's content generation when this cell's view was last supplied.
    private(set) var contentGeneration = 0

    func setup(view: Content, id: AnyHashable? = nil, generation: Int = 0) {
        contentGeneration = generation
        let root = AnyView(view.id(id))
        if let hostingController {
            hostingController.rootView = root
            return
        }
        let controller = UIHostingController(rootView: root)
        // The row owns its content insets. Individual cells must keep their
        // full content bounds as they pass underneath surrounding bars.
        controller.safeAreaRegions.remove(.container)
        controller.view.backgroundColor = nil
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        hostingController = controller
    }
}
#endif
