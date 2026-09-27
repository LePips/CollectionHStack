#if canImport(UIKit)
import SwiftUI

final class HostingCollectionViewCell<Content: View>: UICollectionViewCell {
    private var hostingController: UIHostingController<AnyView>?
    private(set) var representedID: AnyHashable?

    override func prepareForReuse() {
        super.prepareForReuse()
        ResizeAnimation.remove(from: layer)
        representedID = nil
    }

    func setup(view: Content, id: AnyHashable? = nil) {
        if representedID != id {
            ResizeAnimation.remove(from: layer)
        }
        representedID = id
        let root = AnyView(view.id(id))
        if let hostingController {
            hostingController.rootView = root
            return
        }
        let controller = UIHostingController(rootView: root)
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
