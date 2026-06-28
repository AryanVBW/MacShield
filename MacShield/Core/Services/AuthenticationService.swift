import LocalAuthentication
import Foundation

/// Handles Touch ID and password authentication.
final class AuthenticationService {
    static let shared = AuthenticationService()

    /// Whether a Touch ID evaluation is currently in progress.
    private(set) var isAuthenticating = false

    /// The active LAContext — kept so it can be cancelled on overlay dismiss.
    private var activeContext: LAContext?

    private init() {}

    /// Attempt Touch ID authentication.
    /// Concurrent calls are silently ignored — only one evaluatePolicy at a time.
    func authenticateWithTouchID(reason: String = "Unlock this app", completion: @escaping (AuthResult) -> Void) {
        guard !isAuthenticating else {
            NSLog("[MacShield] Touch ID already in progress — ignoring duplicate call")
            return
        }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            let authError = mapLAError(error)
            completion(.failure(authError))
            return
        }

        isAuthenticating = true
        activeContext = context

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                self.activeContext = nil

                if success {
                    completion(.success)
                } else if let error = error as? LAError, error.code == .userCancel {
                    completion(.cancelled)
                } else {
                    let authError = self.mapLAError(error as NSError?)
                    completion(.failure(authError))
                }
            }
        }
    }

    /// Cancel any in-progress Touch ID evaluation (called when overlay is dismissed externally).
    func cancelAuthentication() {
        activeContext?.invalidate()
        activeContext = nil
        isAuthenticating = false
    }

    /// Verify a typed password for a specific protected app.
    ///
    /// Routing:
    /// - If the app has its own **privacy password**, that is the ONLY password accepted
    ///   (the global backup password intentionally does not open it — the escape hatch is
    ///   Settings, which is gated by system Touch ID / login password).
    /// - Otherwise the **global backup password** is used (original behaviour).
    func authenticateWithPassword(_ password: String, for bundleIdentifier: String?) -> AuthResult {
        let keychain = KeychainManager.shared

        if let bundleIdentifier, keychain.hasPassword(forApp: bundleIdentifier) {
            return keychain.verifyPassword(password, forApp: bundleIdentifier)
                ? .success : .failure(.wrongPassword)
        }

        guard keychain.hasPassword() else { return .failure(.noPasswordSet) }
        return keychain.verifyPassword(password) ? .success : .failure(.wrongPassword)
    }

    /// Verify a typed password against the global backup password.
    func authenticateWithPassword(_ password: String) -> AuthResult {
        authenticateWithPassword(password, for: nil)
    }

    /// Check if Touch ID is available on this Mac.
    var isTouchIDAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    // MARK: - Private

    private func mapLAError(_ error: NSError?) -> AuthError {
        guard let error else { return .systemError("Unknown error") }

        switch LAError.Code(rawValue: error.code) {
        case .biometryNotAvailable:
            return .biometryNotAvailable
        case .biometryNotEnrolled:
            return .biometryNotEnrolled
        case .biometryLockout:
            return .biometryLockout
        default:
            return .systemError(error.localizedDescription)
        }
    }
}
