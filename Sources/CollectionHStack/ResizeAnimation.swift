import QuartzCore

/// Animates only the presentation of retained, visible items. Layout and hit testing
/// use the final geometry immediately; no display link or per-frame measurement.
@MainActor
struct ResizeAnimation {
    static let key = "CollectionHStack.resize"
    static let duration: CFTimeInterval = 0.18

    struct Item {
        let id: AnyHashable
        let layer: CALayer
    }

    private struct Snapshot {
        let id: AnyHashable
        let frame: CGRect
    }

    private var snapshots: [ObjectIdentifier: Snapshot] = [:]

    init(items: [Item], in container: CALayer?, enabled: Bool) {
        guard enabled, let container else {
            items.forEach { Self.remove(from: $0.layer) }
            return
        }
        for item in items {
            let layer = item.layer.presentation() ?? item.layer
            let reference = item.layer.presentation() == nil ? container : (container.presentation() ?? container)
            let frame = layer.convert(layer.bounds, to: reference)
            snapshots[ObjectIdentifier(item.layer)] = Snapshot(id: item.id, frame: frame)
        }
    }

    func apply(to items: [Item], in container: CALayer?) {
        guard !snapshots.isEmpty, let container else { return }
        for item in items {
            guard let snapshot = snapshots[ObjectIdentifier(item.layer)], snapshot.id == item.id else { continue }
            // Map viewport coordinates back into the item's current parent. This
            // also handles AppKit's flipped document view and restored scroll anchor.
            let target = item.layer.frame
            let source = container.convert(snapshot.frame, to: item.layer.superlayer)
            guard [source.width, source.height, target.width, target.height].allSatisfy({ $0.isFinite && $0 > 0 }),
                  [source.minX, source.minY, target.minX, target.minY].allSatisfy(\.isFinite) else { continue }
            Self.remove(from: item.layer)
            guard source != target else { continue }

            var transform = CATransform3DMakeScale(source.width / target.width, source.height / target.height, 1)
            // Respect AppKit's zero anchor point as well as UIKit's centered one.
            transform.m41 = source.minX - target.minX + (source.width - target.width) * item.layer.anchorPoint.x
            transform.m42 = source.minY - target.minY + (source.height - target.height) * item.layer.anchorPoint.y
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: transform)
            animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            animation.isAdditive = true
            animation.duration = Self.duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            // Replacing one keyed animation retargets from the captured presentation
            // frame without building up a queue during live window resizing.
            item.layer.add(animation, forKey: Self.key)
        }
    }

    static func remove(from layer: CALayer) {
        layer.removeAnimation(forKey: key)
    }
}
