import AppKit
import Combine

/// Main orchestrator for the Chat Blur feature.
/// Monitors app activations and shows/hides blur overlays for configured chat apps.
final class BlurOverlayService: ObservableObject {
    static let shared = BlurOverlayService()

    @Published var isBlurActive: Bool = false {
        didSet {
            if isBlurActive {
                startMonitoring()
            } else {
                stopMonitoring()
                BlurWindowManager.shared.removeAll()
            }
            // Persist the setting
            var settings = Defaults.shared.appSettings
            settings.isBlurEnabled = isBlurActive
            Defaults.shared.appSettings = settings
        }
    }

    @Published var blurIntensity: Double = 8.0 {
        didSet { syncSettings() }
    }

    @Published var revealRadius: Double = 200.0 {
        didSet { syncSettings() }
    }

    @Published var revealOnHover: Bool = true {
        didSet { syncSettings() }
    }

    /// Bundle IDs of apps to blur (loaded from Defaults).
    @Published var blurredApps: [BlurredApp] = []

    private var cancellables = Set<AnyCancellable>()
    private var isMonitoring = false

    /// The PID of the currently blurred foreground app (if any).
    private var activeBlurPID: pid_t?

    private init() {
        loadSettings()
    }

    // MARK: - Public

    /// Initialize from persisted settings. Called from AppDelegate.
    func loadSettings() {
        let settings = Defaults.shared.appSettings
        blurIntensity = settings.blurIntensity
        revealRadius = settings.revealRadius
        revealOnHover = settings.revealOnHover
        blurredApps = Defaults.shared.blurredApps

        // Set isBlurActive last to trigger startMonitoring if needed
        isBlurActive = settings.isBlurEnabled
    }

    /// Toggle blur for a specific app.
    func toggleApp(_ app: BlurredApp) {
        guard let index = blurredApps.firstIndex(where: { $0.id == app.id }) else { return }
        blurredApps[index].isEnabled.toggle()
        Defaults.shared.blurredApps = blurredApps

        // If the app is currently blurred and was disabled, remove overlay
        if !blurredApps[index].isEnabled {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == app.bundleIdentifier
            }) {
                BlurWindowManager.shared.removeOverlay(for: runningApp.processIdentifier)
            }
        }
    }

    /// Check whether a bundle ID is in the blur list and enabled.
    func shouldBlur(_ bundleIdentifier: String) -> Bool {
        guard isBlurActive else { return false }
        return blurredApps.contains { $0.bundleIdentifier == bundleIdentifier && $0.isEnabled }
    }

    /// Show blur overlay for the given running app.
    func showBlurOverlay(for app: NSRunningApplication) {
        guard isBlurActive else { return }
        guard let bundleID = app.bundleIdentifier, shouldBlur(bundleID) else { return }
        guard !SafetyManager.isBlacklisted(bundleID) else { return }

        let settings = Defaults.shared.appSettings
        _ = BlurWindowManager.shared.createOverlay(for: app, settings: settings)
        activeBlurPID = app.processIdentifier
    }

    /// Hide blur overlay for the given app.
    func hideBlurOverlay(for app: NSRunningApplication) {
        BlurWindowManager.shared.removeOverlay(for: app.processIdentifier)
        if activeBlurPID == app.processIdentifier {
            activeBlurPID = nil
        }
    }

    /// Dismiss all blur overlays (panic key, etc.).
    func dismissAll() {
        BlurWindowManager.shared.removeAll()
        activeBlurPID = nil
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Prompt for Screen Recording permission if not yet granted
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        let workspace = NSWorkspace.shared

        // Monitor app activations — show blur when a blurred app comes to foreground
        workspace.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in
                self?.handleAppActivation(app)
            }
            .store(in: &cancellables)

        // Monitor app deactivation — hide blur when app loses focus
        workspace.notificationCenter.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in
                self?.handleAppDeactivation(app)
            }
            .store(in: &cancellables)

        // Monitor app termination — clean up overlays
        workspace.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in
                self?.hideBlurOverlay(for: app)
            }
            .store(in: &cancellables)

        // Check if a blurred app is already the frontmost
        if let frontApp = workspace.frontmostApplication {
            handleAppActivation(frontApp)
        }

        NSLog("[MacShield] Blur monitoring started")
    }

    private func stopMonitoring() {
        cancellables.removeAll()
        isMonitoring = false
        NSLog("[MacShield] Blur monitoring stopped")
    }

    private func handleAppActivation(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }

        if shouldBlur(bundleID) {
            showBlurOverlay(for: app)
        }
    }

    private func handleAppDeactivation(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }

        if shouldBlur(bundleID) {
            hideBlurOverlay(for: app)
        }
    }

    // MARK: - Settings Sync

    private func syncSettings() {
        var settings = Defaults.shared.appSettings
        settings.blurIntensity = blurIntensity
        settings.revealRadius = revealRadius
        settings.revealOnHover = revealOnHover
        Defaults.shared.appSettings = settings

        BlurWindowManager.shared.updateSettings(settings)
    }
}
