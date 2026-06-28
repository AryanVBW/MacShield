import AppKit

/// Gates access to MacShield's own controls — opening the menu-bar popover (which leads to
/// Settings, the protection toggle, and Quit).
///
/// Security policy: the macOS **login/root password does NOT unlock MacShield**. The only
/// accepted credentials are Touch ID (biometrics) or MacShield's own backup password, or an
/// Apple Watch on wrist. This is what prevents someone who merely knows the Mac's login
/// password from disabling protection or quitting the app.
///
/// Safety valve: if the user has configured neither Touch ID nor a backup password, access is
/// allowed — otherwise they could never reach Settings to set one up.
final class SettingsAuthService {
    static let shared = SettingsAuthService()

    private init() {}

    /// Whether Apple Watch can bypass the challenge (on wrist + in range).
    var canWatchBypass: Bool {
        let settings = Defaults.shared.appSettings
        let watch = WatchProximityService.shared
        return settings.useWatchUnlock
            && watch.isWatchInRange
            && (watch.isWatchUnlocked ?? true)
    }

    /// True when no MacShield credential exists at all (no Touch ID, no backup password).
    private var hasNoAuthMethod: Bool {
        !AuthenticationService.shared.isTouchIDAvailable
            && !KeychainManager.shared.hasPassword()
    }

    /// Authenticate before opening the menu-bar popover (Settings / toggle / Quit).
    func authenticate(completion: @escaping (Bool) -> Void) {
        // Safety valve: nothing configured to authenticate against.
        if hasNoAuthMethod {
            completion(true)
            return
        }

        // Apple Watch on wrist bypasses with a toast.
        if canWatchBypass {
            completion(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WatchUnlockToast.shared.show()
            }
            return
        }

        // Don't double-trigger if Touch ID is already in progress (e.g. an app-lock overlay).
        guard !AuthenticationService.shared.isAuthenticating else {
            completion(false)
            return
        }

        // Touch ID first (biometrics only — never the login password). On cancel/failure,
        // fall back to MacShield's own backup password, NOT the system password.
        if AuthenticationService.shared.isTouchIDAvailable {
            AuthenticationService.shared.authenticateWithTouchID(
                reason: "Access MacShield"
            ) { [weak self] result in
                switch result {
                case .success:
                    completion(true)
                case .cancelled, .failure:
                    self?.promptForMacShieldPassword(completion: completion)
                }
            }
        } else {
            promptForMacShieldPassword(completion: completion)
        }
    }

    /// Prompt for MacShield's own backup password via a native secure dialog.
    /// The macOS login password is explicitly not accepted here.
    private func promptForMacShieldPassword(completion: @escaping (Bool) -> Void) {
        guard KeychainManager.shared.hasPassword() else {
            // Touch ID exists but failed, and there's no backup password to fall back to.
            completion(false)
            return
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Enter MacShield Password"
            alert.informativeText = "Enter your MacShield password to continue. Your macOS login password will not unlock MacShield."
            alert.alertStyle = .informational

            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.placeholderString = "MacShield password"
            alert.accessoryView = field

            alert.addButton(withTitle: "Unlock")
            alert.addButton(withTitle: "Cancel")

            NSApp.activate(ignoringOtherApps: true)
            alert.window.initialFirstResponder = field

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completion(KeychainManager.shared.verifyPassword(field.stringValue))
            } else {
                completion(false)
            }
        }
    }
}
