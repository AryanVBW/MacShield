import AppKit
import Combine

/// Manages the list of protected applications with CRUD operations and persistence.
final class ProtectedAppsManager: ObservableObject {
    static let shared = ProtectedAppsManager()

    @Published private(set) var apps: [ProtectedApp] = []

    private init() {
        let cached = Defaults.shared.protectedApps

        if let data = KeychainManager.shared.loadProtectedAppsBackup(),
           let backup = try? JSONDecoder().decode([ProtectedApp].self, from: data) {
            // The Keychain backup is authoritative. It resists tampering with the
            // preferences plist (~/Library/Preferences/com.macshield.app.plist), which
            // any logged-in process can edit with no password at all. If the cached copy
            // was altered out from under us (e.g. someone deleted protected entries),
            // restore the real list so protection can't be stripped by editing prefs.
            apps = backup
            if backup != cached {
                Defaults.shared.protectedApps = backup
                NSLog("[MacShield] Protected-apps list restored from secure backup (prefs mismatch detected)")
            }
        } else {
            // First run / upgrade from a build without the backup: seed it from prefs.
            apps = cached
            writeBackup()
        }
    }

    /// Add an application to the protected list.
    func addApp(bundleIdentifier: String, name: String, path: String) {
        guard !apps.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }

        let app = ProtectedApp(
            bundleIdentifier: bundleIdentifier,
            name: name,
            path: path
        )
        apps.append(app)
        save()
        NSLog("[MacShield] Added protected app: %@ (%@)", name, bundleIdentifier)
    }

    /// Add an app from an NSRunningApplication.
    func addApp(from runningApp: NSRunningApplication) {
        guard let bundleID = runningApp.bundleIdentifier,
              let name = runningApp.localizedName,
              let url = runningApp.bundleURL else { return }

        addApp(bundleIdentifier: bundleID, name: name, path: url.path)
    }

    /// Remove an application from the protected list.
    func removeApp(_ app: ProtectedApp) {
        apps.removeAll { $0.id == app.id }
        // The privacy password is per-app — remove it from the Keychain too so a
        // re-added app doesn't silently inherit an old secret.
        KeychainManager.shared.deletePassword(forApp: app.bundleIdentifier)
        save()
        NSLog("[MacShield] Removed protected app: %@", app.name)
    }

    /// Toggle protection on or off for an app.
    func toggleApp(_ app: ProtectedApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].isEnabled.toggle()
        save()
    }

    /// Toggle auto-close on or off for an app.
    func toggleAutoClose(_ app: ProtectedApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].autoClose.toggle()
        save()

        // Cancel pending timer if auto-close was disabled
        if !apps[index].autoClose {
            AppInactivityService.shared.cancelTimer(for: app.bundleIdentifier)
        }
    }

    /// Set whether Touch ID / Apple Watch may unlock this app.
    /// When disabled, only the app's privacy password unlocks it.
    func setAllowBiometric(_ allow: Bool, for app: ProtectedApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].allowBiometric = allow
        save()
    }

    // MARK: - Per-App Privacy Password

    /// Whether this app has its own privacy password (distinct from the global backup password).
    func hasCustomPassword(_ app: ProtectedApp) -> Bool {
        KeychainManager.shared.hasPassword(forApp: app.bundleIdentifier)
    }

    /// Set (or replace) this app's privacy password. Returns false if the Keychain write failed.
    @discardableResult
    func setPassword(_ password: String, for app: ProtectedApp) -> Bool {
        let ok = KeychainManager.shared.savePassword(password, forApp: app.bundleIdentifier)
        if ok { objectWillChange.send() }   // refresh the per-app password indicator
        return ok
    }

    /// Remove this app's privacy password — it falls back to the global backup password.
    func removePassword(for app: ProtectedApp) {
        KeychainManager.shared.deletePassword(forApp: app.bundleIdentifier)
        objectWillChange.send()
    }

    /// Check whether an app with the given bundle identifier is protected and enabled.
    func isProtected(_ bundleIdentifier: String) -> Bool {
        return apps.contains { $0.bundleIdentifier == bundleIdentifier && $0.isEnabled }
    }

    private func save() {
        Defaults.shared.protectedApps = apps
        writeBackup()
    }

    /// Mirror the protected-apps list into the Keychain as a tamper-resistant backup.
    private func writeBackup() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        KeychainManager.shared.saveProtectedAppsBackup(data)
    }
}
