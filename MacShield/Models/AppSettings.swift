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
    var requireAuthOnActivate: Bool = true

    /// Use Apple Watch proximity for auto-unlock.
    var useWatchUnlock: Bool = false

    /// Watch RSSI threshold for proximity detection.
    /// Default: -70 dBm (~2-3 meters). Higher (less negative) = stricter.
    var watchRssiThreshold: Int = -70

    /// Inactivity timeout (minutes) before auto-closing protected apps that have autoClose enabled.
    var inactiveCloseMinutes: Int = 15

    /// Launch MacShield at login.
    var launchAtLogin: Bool = false

    /// Tamper resistance: relaunch MacShield automatically if it is force-quit or killed.
    /// A clean Quit (from the gated menu) still exits normally and is not relaunched.
    var keepRunning: Bool = false

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

// MARK: - Resilient Decoding

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case isProtectionEnabled, lockOnSleep, lockOnIdle, idleTimeoutMinutes,
             requireAuthOnLaunch, requireAuthOnActivate, useWatchUnlock,
             watchRssiThreshold, inactiveCloseMinutes, launchAtLogin, keepRunning,
             isBlurEnabled, blurIntensity, revealRadius, revealOnHover,
             blurFeatherWidth, blurAnimatesIn
    }

    /// Tolerant decoding: any key absent from older persisted settings keeps its
    /// default instead of throwing — which would otherwise reset ALL settings
    /// whenever a new field is introduced in an app update.
    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        isProtectionEnabled   = (try? c.decode(Bool.self,   forKey: .isProtectionEnabled))   ?? isProtectionEnabled
        lockOnSleep           = (try? c.decode(Bool.self,   forKey: .lockOnSleep))           ?? lockOnSleep
        lockOnIdle            = (try? c.decode(Bool.self,   forKey: .lockOnIdle))            ?? lockOnIdle
        idleTimeoutMinutes    = (try? c.decode(Int.self,    forKey: .idleTimeoutMinutes))    ?? idleTimeoutMinutes
        requireAuthOnLaunch   = (try? c.decode(Bool.self,   forKey: .requireAuthOnLaunch))   ?? requireAuthOnLaunch
        requireAuthOnActivate = (try? c.decode(Bool.self,   forKey: .requireAuthOnActivate)) ?? requireAuthOnActivate
        useWatchUnlock        = (try? c.decode(Bool.self,   forKey: .useWatchUnlock))        ?? useWatchUnlock
        watchRssiThreshold    = (try? c.decode(Int.self,    forKey: .watchRssiThreshold))    ?? watchRssiThreshold
        inactiveCloseMinutes  = (try? c.decode(Int.self,    forKey: .inactiveCloseMinutes))  ?? inactiveCloseMinutes
        launchAtLogin         = (try? c.decode(Bool.self,   forKey: .launchAtLogin))         ?? launchAtLogin
        keepRunning           = (try? c.decode(Bool.self,   forKey: .keepRunning))           ?? keepRunning
        isBlurEnabled         = (try? c.decode(Bool.self,   forKey: .isBlurEnabled))         ?? isBlurEnabled
        blurIntensity         = (try? c.decode(Double.self, forKey: .blurIntensity))         ?? blurIntensity
        revealRadius          = (try? c.decode(Double.self, forKey: .revealRadius))          ?? revealRadius
        revealOnHover         = (try? c.decode(Bool.self,   forKey: .revealOnHover))         ?? revealOnHover
        blurFeatherWidth      = (try? c.decode(Double.self, forKey: .blurFeatherWidth))      ?? blurFeatherWidth
        blurAnimatesIn        = (try? c.decode(Bool.self,   forKey: .blurAnimatesIn))        ?? blurAnimatesIn
    }
}
