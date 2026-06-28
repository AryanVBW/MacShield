import AppKit
import SwiftUI

/// Manages overlay window lifecycle: show, hide, and timeout failsafe.
final class OverlayWindowService {
    static let shared = OverlayWindowService()

    private var overlayWindows: [LockOverlayWindow] = []
    private var timeoutTimer: Timer?
    private var currentApp: ProtectedApp?

    /// Callback when overlay is dismissed after successful authentication.
    /// Passes the name of the unlocked app.
    var onUnlocked: ((String) -> Void)?

    private init() {
        // Observe screen configuration changes (connect/disconnect monitors)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Show the lock overlay for a protected app on all screens.
    func show(for app: ProtectedApp) {
        // Don't show duplicate overlays
        guard overlayWindows.isEmpty else { return }

        currentApp = app

        // Don't hide the protected app — the overlay blur covers its content,
        // and hiding it causes macOS to reassign app focus, which interferes
        // with the system Touch ID dialog.

        createOverlayWindows(for: app)
        startTimeoutTimer()

        NSLog("[MacShield] Overlay shown for: %@", app.name)
    }

    /// Unlock: dismiss overlays AFTER successful authentication. Marks the app
    /// authenticated for this session and brings it forward.
    func unlock() {
        dismiss(authenticated: true)
    }

    /// Dismiss all overlays WITHOUT authentication (panic key, timeout failsafe).
    /// Fails closed: the protected app is concealed and stays locked — never revealed.
    func dismissAll() {
        dismiss(authenticated: false)
    }

    /// Core dismissal.
    ///
    /// - `authenticated == true`  → the user passed Touch ID / password / Watch: mark the
    ///   app authenticated and bring it forward.
    /// - `authenticated == false` → no auth happened (60s timeout or panic key): NEVER grant
    ///   access. Keep the app un-authenticated and hide its windows so removing the overlay
    ///   can't expose protected content. The next activation re-locks it.
    private func dismiss(authenticated: Bool) {
        stopTimeoutTimer()

        // Cancel any in-progress Touch ID evaluation
        AuthenticationService.shared.cancelAuthentication()

        let bundleID = currentApp?.bundleIdentifier

        if authenticated, let bundleID {
            AppMonitorService.shared.markAuthenticated(bundleID)
        }

        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()

        if let bundleID {
            if authenticated {
                // Bring the app forward now that overlays are gone. Small delay ensures
                // panels and the Touch ID dialog are fully dismissed first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.activateProtectedApp(bundleIdentifier: bundleID)
                }
            } else {
                // Fail closed: conceal the app's windows and keep it locked.
                AppMonitorService.shared.clearAuthentication(for: bundleID)
                hideRunningApp(bundleIdentifier: bundleID)
            }
        }

        currentApp = nil
        NSLog("[MacShield] Overlay %@", authenticated ? "unlocked" : "dismissed (locked down)")
    }

    /// Whether an overlay is currently displayed.
    var isShowing: Bool {
        !overlayWindows.isEmpty
    }

    /// Bundle identifier of the currently locked app (if any).
    var currentBundleIdentifier: String? {
        currentApp?.bundleIdentifier
    }

    /// Display name of the currently locked app (if any).
    var currentAppName: String? {
        currentApp?.name
    }

    /// During Touch ID: pass through mouse events so system dialog gets interaction.
    /// After auth: restore mouse capture for overlay blocking.
    func setTouchIDMode(_ active: Bool) {
        for window in overlayWindows {
            window.ignoresMouseEvents = active
        }
    }

    /// Enable key window status on overlay windows (needed for password input).
    func enableKeyboardInput() {
        setTouchIDMode(false)
        for window in overlayWindows {
            window.allowKeyStatus = true
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Screen Management

    @objc private func screensDidChange(_ notification: Notification) {
        guard !overlayWindows.isEmpty else { return }

        let screens = NSScreen.screens

        // Reposition existing windows to match current screens (don't recreate to avoid re-triggering Touch ID)
        for (index, window) in overlayWindows.enumerated() {
            if index < screens.count {
                window.reposition(to: screens[index])
            }
        }

        // Close excess windows if screens were removed
        while overlayWindows.count > screens.count {
            overlayWindows.removeLast().close()
        }

        // Add new windows for new screens (only blur, no Touch ID trigger)
        if let app = currentApp {
            for screenIndex in overlayWindows.count..<screens.count {
                let window = LockOverlayWindow(for: screens[screenIndex])
                let overlayView = LockOverlayView(
                    appName: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    isPrimary: false,
                    allowBiometric: app.allowBiometric,
                    onDismiss: { [weak self] in
                        let name = self?.currentApp?.name ?? "app"
                        self?.unlock()
                        self?.onUnlocked?(name)
                    }
                )
                window.contentView = NSHostingView(rootView: overlayView)
                window.orderFront(nil)
                overlayWindows.append(window)
            }
        }

        NSLog("[MacShield] Overlays repositioned for screen change (%d screens)", screens.count)
    }

    private func createOverlayWindows(for app: ProtectedApp) {
        let primaryScreen = NSScreen.main ?? NSScreen.screens.first

        for screen in NSScreen.screens {
            let window = LockOverlayWindow(for: screen)
            let isPrimary = (screen == primaryScreen)

            let overlayView = LockOverlayView(
                appName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                isPrimary: isPrimary,
                allowBiometric: app.allowBiometric,
                onDismiss: { [weak self] in
                    let name = self?.currentApp?.name ?? "app"
                    self?.unlock()
                    self?.onUnlocked?(name)
                }
            )

            window.contentView = NSHostingView(rootView: overlayView)
            // Don't make key or activate — system Touch ID dialog needs focus
            window.orderFront(nil)
            overlayWindows.append(window)
        }
    }

    // MARK: - App Window Management

    /// Bring the protected app to the foreground after successful auth.
    /// Only activates if the app is already running — never launches a closed app.
    private func activateProtectedApp(bundleIdentifier: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            NSLog("[MacShield] App not running, skipping activation: %@", bundleIdentifier)
            return
        }
        app.activate()
        NSLog("[MacShield] Activated app: %@", bundleIdentifier)
    }

    /// Conceal a running app's windows (used on fail-closed dismiss) so removing the
    /// overlay never exposes protected content. Equivalent to Cmd+H on the app.
    private func hideRunningApp(bundleIdentifier: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return }
        app.hide()
        NSLog("[MacShield] Concealed app on locked-down dismiss: %@", bundleIdentifier)
    }

    // MARK: - Timeout

    private func startTimeoutTimer() {
        let timeout = SafetyManager.isDevMode
            ? SafetyManager.devModeTimeout
            : SafetyManager.overlayTimeout

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            NSLog("[MacShield Safety] Overlay timeout reached (%.0fs) — locking down (no access granted)", timeout)
            self?.dismiss(authenticated: false)
        }
    }

    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

}
