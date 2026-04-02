import Foundation

/// Centralized UserDefaults wrapper for MacShield settings.
final class Defaults {
    static let shared = Defaults()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key: String {
        case protectedApps
        case blurredApps
        case appSettings
        case hasCompletedOnboarding
        case backupPasswordSet
    }

    private init() {}

    // MARK: - Protected Apps

    /// Persisted list of protected applications.
    var protectedApps: [ProtectedApp] {
        get {
            guard let data = defaults.data(forKey: Key.protectedApps.rawValue),
                  let apps = try? decoder.decode([ProtectedApp].self, from: data) else {
                return []
            }
            return apps
        }
        set {
            let data = try? encoder.encode(newValue)
            defaults.set(data, forKey: Key.protectedApps.rawValue)
        }
    }

    // MARK: - App Settings

    /// User preferences for MacShield behavior.
    var appSettings: AppSettings {
        get {
            guard let data = defaults.data(forKey: Key.appSettings.rawValue),
                  let settings = try? decoder.decode(AppSettings.self, from: data) else {
                return AppSettings()
            }
            return settings
        }
        set {
            let data = try? encoder.encode(newValue)
            defaults.set(data, forKey: Key.appSettings.rawValue)
        }
    }

    // MARK: - Blurred Apps

    /// Persisted list of apps to blur.
    var blurredApps: [BlurredApp] {
        get {
            guard let data = defaults.data(forKey: Key.blurredApps.rawValue),
                  let apps = try? decoder.decode([BlurredApp].self, from: data) else {
                return BlurredApp.defaultApps
            }
            return apps
        }
        set {
            let data = try? encoder.encode(newValue)
            defaults.set(data, forKey: Key.blurredApps.rawValue)
        }
    }

    // MARK: - Flags

    /// Whether the user has completed first-launch onboarding.
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding.rawValue) }
    }

    /// Whether a backup password has been configured.
    var isBackupPasswordSet: Bool {
        get { defaults.bool(forKey: Key.backupPasswordSet.rawValue) }
        set { defaults.set(newValue, forKey: Key.backupPasswordSet.rawValue) }
    }
}
