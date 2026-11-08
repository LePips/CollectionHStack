#if canImport(UIKit)
import SwiftUI

final class HostingCollectionViewCell<Content: View>: UICollectionViewCell {
    private var hostingController: UIHostingController<CollectionItemContent<Content>>?
    /// The collection's content generation when this cell's view was last supplied.
    private(set) var contentGeneration = 0

    func setup(view: Content, id: AnyHashable? = nil, generation: Int = 0, environment: EnvironmentValues? = nil) {
        contentGeneration = generation
        let root = CollectionItemContent(content: view, identity: id, environment: environment)
        if let hostingController {
            hostingController.rootView = root
            return
        }
        let controller = UIHostingController(rootView: root)
        // The enclosing collection owns viewport and keyboard avoidance. A nested
        // host must not apply either again; iOS 18 can treat a partially offscreen
        // cell's bottom inset as a keyboard inset and shift its content upward.
        controller.safeAreaRegions = []
        controller.view.backgroundColor = nil
        // All HStack layouts supply measured item bounds, including variadic widths.
        controller.view.frame = contentView.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(controller.view)
        hostingController = controller
    }
}
#endif
