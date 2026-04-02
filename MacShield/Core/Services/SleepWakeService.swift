import Foundation
import AppKit

/// Monitors system sleep/wake events and triggers auto-lock on sleep.
final class SleepWakeService {
    static let shared = SleepWakeService()

    /// Callback when the system is about to sleep.
    var onSleep: (() -> Void)?

    /// Callback when the system wakes from sleep.
    var onWake: (() -> Void)?

    private var isObserving = false

    private init() {}

    /// Begin observing sleep/wake notifications.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NSLog("[MacShield] Sleep/wake observer started")
    }

    /// Stop observing sleep/wake notifications.
    func stopObserving() {
        guard isObserving else { return }
        isObserving = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NSLog("[MacShield] Sleep/wake observer stopped")
    }

    // MARK: - Handlers

    @objc private func handleSleep(_ notification: Notification) {
        NSLog("[MacShield] System going to sleep")
        onSleep?()
    }

    @objc private func handleWake(_ notification: Notification) {
        NSLog("[MacShield] System woke from sleep")
        onWake?()
    }
}
