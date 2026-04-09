import Foundation

/// Persisted user preferences.
struct AppSettings: Codable {
    /// Whether MacShield protection is globally active.
    var isProtectionEnabled: Bool = true

    /// Lock apps when the Mac goes to sleep.
    var lockOnSleep: Bool = true

    /// Lock apps after idle timeout.
    var lockOnIdle: Bool = false

    /// Idle timeout in minutes before auto-lock triggers.
    var idleTimeoutMinutes: Int = 5

    /// Require authentication when a protected app is launched.
    var requireAuthOnLaunch: Bool = true

    /// Require authentication when switching to a protected app.
    var requireAuthOnActivate: Bool = false

    /// Use Apple Watch proximity for auto-unlock.
    var useWatchUnlock: Bool = false

    /// Watch RSSI threshold for proximity detection.
    /// Default: -70 dBm (~2-3 meters). Higher (less negative) = stricter.
    var watchRssiThreshold: Int = -70

    /// Inactivity timeout (minutes) before auto-closing protected apps that have autoClose enabled.
    var inactiveCloseMinutes: Int = 15

    /// Launch MacShield at login.
    var launchAtLogin: Bool = false

    // MARK: - Chat Blur

    /// Whether chat blur is globally enabled.
    var isBlurEnabled: Bool = false

    /// Blur intensity mapped to tint opacity (2–20).
    var blurIntensity: Double = 8.0

    /// Radius in points of the clear reveal zone around the cursor.
    var revealRadius: Double = 200.0

    /// Reveal mode: hover to reveal or click to reveal.
    var revealOnHover: Bool = true

    /// Width of the soft feathered edge on the reveal zone (0.10–0.50).
    /// 0.10 = very sharp edge, 0.50 = very gradual fade.
    var blurFeatherWidth: Double = 0.28

    /// Whether the blur overlay should animate in when it first appears.
    var blurAnimatesIn: Bool = true
}
