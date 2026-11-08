import Foundation

/// A trailing update with one pending callback. Repeated requests move its
/// deadline and replace its action instead of queuing cancelled work each frame.
@MainActor
final class CollectionDeferredUpdate {
    private var deadline: TimeInterval = 0
    private var action: (@MainActor () -> Void)?
    private var isScheduled = false

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        deadline = ProcessInfo.processInfo.systemUptime + delay
        self.action = action
        guard !isScheduled else { return }

        enqueue(after: delay)
    }

    func cancel() {
        action = nil
    }

    private func enqueue(after delay: TimeInterval) {
        isScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            guard let self else { return }

            self.isScheduled = false
            guard let action = self.action else { return }

            let remaining = self.deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                self.enqueue(after: remaining)
            } else {
                self.action = nil
                action()
            }
        }
    }
}
