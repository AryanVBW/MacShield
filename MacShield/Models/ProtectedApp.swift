import Foundation

/// An application that the user has chosen to protect with MacShield.
struct ProtectedApp: Codable, Identifiable, Hashable {
    /// Unique identifier for this entry.
    let id: UUID

    /// The app's bundle identifier (e.g. "com.apple.Safari").
    let bundleIdentifier: String

    /// Display name (e.g. "Safari").
    let name: String

    /// Path to the application bundle on disk.
    let path: String

    /// Whether protection is currently enabled for this app.
    var isEnabled: Bool

    /// Whether to auto-close this app after inactivity timeout.
    /// When enabled, the app will be terminated after the global inactive timeout
    /// to prevent notifications from appearing while the app is locked.
    var autoClose: Bool

    /// Whether Touch ID / Apple Watch may unlock this app.
    /// When `false`, the app can ONLY be unlocked by typing its password — a true
    /// "private" lock where a fingerprint is not enough. Defaults to `true` so
    /// existing apps keep the familiar Touch-ID-first behaviour.
    var allowBiometric: Bool

    /// Date the app was added to the protected list.
    let dateAdded: Date

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        name: String,
        path: String,
        isEnabled: Bool = true,
        autoClose: Bool = false,
        allowBiometric: Bool = true,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
        self.autoClose = autoClose
        self.allowBiometric = allowBiometric
        self.dateAdded = dateAdded
    }
}

// MARK: - Resilient Decoding

extension ProtectedApp {
    private enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, name, path, isEnabled, autoClose, allowBiometric, dateAdded
    }

    /// Tolerant decoding: newer fields (e.g. `allowBiometric`) absent from apps
    /// persisted by an older build keep their default instead of throwing — which
    /// would otherwise make the WHOLE `[ProtectedApp]` array fail to decode and
    /// silently wipe the user's protected-app list on update.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Identity fields have existed in every historical record.
        let bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        let name = try c.decode(String.self, forKey: .name)
        let path = try c.decode(String.self, forKey: .path)
        self.init(
            id: (try? c.decode(UUID.self, forKey: .id)) ?? UUID(),
            bundleIdentifier: bundleIdentifier,
            name: name,
            path: path,
            isEnabled: (try? c.decode(Bool.self, forKey: .isEnabled)) ?? true,
            autoClose: (try? c.decode(Bool.self, forKey: .autoClose)) ?? false,
            allowBiometric: (try? c.decode(Bool.self, forKey: .allowBiometric)) ?? true,
            dateAdded: (try? c.decode(Date.self, forKey: .dateAdded)) ?? Date()
        )
    }
}
