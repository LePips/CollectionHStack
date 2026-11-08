import Foundation

/// Horizontal anchor semantics shared by UIKit and AppKit. The adapters handle
/// their native coordinate conversion and content-inset conventions.
enum CollectionScrollAnchor {
    case leading
    case trailing
    case page(CGFloat)
    case item(index: Int, fraction: CGFloat, centered: Bool)
}
