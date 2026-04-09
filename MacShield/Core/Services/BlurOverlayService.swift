import AppKit
import Combine

/// Main orchestrator for the Chat Blur feature.
/// Monitors app activations and shows/hides blur overlays for configured chat apps.
///
/// Background blur prevention (belt-and-suspenders):
/// 1. `didDeactivateApplicationNotification` → removes overlay immediately
/// 2. `didActivateApplicationNotification` for a NON-blurred app → removes all overlays
/// 3. BlurWindowManager's refresh timer removes overlays whose PID ≠ frontmostPID
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

    /// Width of the soft feathered edge on the reveal zone (0.10–0.50).
    @Published var featherWidth: Double = 0.28 {
        didSet { syncSettings() }
    }

    /// Whether the blur overlay fades in when first shown.
    @Published var blurAnimatesIn: Bool = true {
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
        blurIntensity  = settings.blurIntensity
        revealRadius   = settings.revealRadius
        revealOnHover  = settings.revealOnHover
        featherWidth   = settings.blurFeatherWidth
        blurAnimatesIn = settings.blurAnimatesIn
        blurredApps    = Defaults.shared.blurredApps

        // Set isBlurActive last to trigger startMonitoring if needed
        isBlurActive = settings.isBlurEnabled
    }

    /// Toggle blur for a specific app.
    func toggleApp(_ app: BlurredApp) {
        guard let index = blurredApps.firstIndex(where: { $0.id == app.id }) else { return }
        blurredApps[index].isEnabled.toggle()
        Defaults.shared.blurredApps = blurredApps

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

    /// Look up the BlurredApp config for a given bundle ID.
    func blurredAppConfig(for bundleIdentifier: String) -> BlurredApp? {
        blurredApps.first { $0.bundleIdentifier == bundleIdentifier && $0.isEnabled }
    }

    /// Known Catalyst / Electron bundle IDs that need a delayed overlay to let
    /// the window frame settle after activation.
    private static let catalystBundleIDs: Set<String> = [
        "net.whatsapp.WhatsApp",
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.facebook.archon",
    ]

    /// Show blur overlay for the given running app.
    func showBlurOverlay(for app: NSRunningApplication) {
        guard isBlurActive else { return }
        guard let bundleID = app.bundleIdentifier, shouldBlur(bundleID) else { return }
        guard !SafetyManager.isBlacklisted(bundleID) else { return }

        let pid = app.processIdentifier
        let config = blurredAppConfig(for: bundleID)
        let insets = config?.contentInsets ?? .none

        // Catalyst apps (WhatsApp, Teams) animate their window into position
        // when activated. Creating the overlay immediately can land on a stale frame.
        let delay: TimeInterval = Self.catalystBundleIDs.contains(bundleID) ? 0.15 : 0
        let createBlock = { [weak self] in
            guard let self, self.isBlurActive else { return }
            // Re-check that the app is still frontmost after the delay
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            let settings = Defaults.shared.appSettings
            _ = BlurWindowManager.shared.createOverlay(for: app, settings: settings, insets: insets)
            self.activeBlurPID = pid
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: createBlock)
        } else {
            createBlock()
        }
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

        let workspace = NSWorkspace.shared

        // App activation: show blur if it's a blurred app, OR remove stale overlays
        workspace.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in self?.handleAppActivation(app) }
            .store(in: &cancellables)

        // App deactivation: remove blur immediately
        workspace.notificationCenter.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in self?.handleAppDeactivation(app) }
            .store(in: &cancellables)

        // App termination: clean up
        workspace.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in self?.hideBlurOverlay(for: app) }
            .store(in: &cancellables)

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
        } else {
            // A NON-blurred app was activated — remove any lingering overlays.
            // This is the belt-and-suspenders fix for background blur sticking:
            // if the deactivation notification was missed (Catalyst edge case),
            // this activation of a different app cleans up.
            if BlurWindowManager.shared.isShowingAny {
                NSLog("[MacShield] Non-blurred app activated (%@) — removing stale overlays", bundleID)
                BlurWindowManager.shared.removeAll()
                activeBlurPID = nil
            }
        }
    }

    private func handleAppDeactivation(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        if shouldBlur(bundleID) { hideBlurOverlay(for: app) }
    }

    // MARK: - Settings Sync

    private func syncSettings() {
        var settings = Defaults.shared.appSettings
        settings.blurIntensity   = blurIntensity
        settings.revealRadius    = revealRadius
        settings.revealOnHover   = revealOnHover
        settings.blurFeatherWidth = featherWidth
        settings.blurAnimatesIn  = blurAnimatesIn
        Defaults.shared.appSettings = settings

        BlurWindowManager.shared.updateSettings(settings)
    }
}
