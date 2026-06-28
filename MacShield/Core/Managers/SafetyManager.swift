import Foundation
import HotKey
import AppKit

/// Manages safety mechanisms to prevent the user from getting locked out.
///
/// Safety features:
/// - Panic key (Cmd+Option+Shift+Control+U) dismisses all overlays instantly
/// - System blacklist prevents locking Terminal, Xcode, and other dev tools
/// - Overlay timeout (60s) auto-dismisses stuck overlays
/// - Dev mode (DEBUG only) adds Skip button and 10s auto-dismiss
final class SafetyManager {
    static let shared = SafetyManager()

    /// Callback invoked when the panic key is pressed.
    var onPanicKeyPressed: (() -> Void)?

    /// Whether dev mode safety features are active.
    static var isDevMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Maximum overlay display time before auto-dismiss (seconds).
    static let overlayTimeout: TimeInterval = 60

    /// Dev mode auto-dismiss time (seconds).
    static let devModeTimeout: TimeInterval = 25

    /// Bundle identifiers that can never be locked.
    static let systemBlacklist: Set<String> = [
        // Apple system apps
        "com.apple.Terminal",
        "com.apple.finder",
        "com.apple.ActivityMonitor",
        "com.apple.systempreferences",          // Monterey and earlier
        "com.apple.SystemSettings",              // Ventura+
        "com.apple.System-Preferences",

        // Development tools
        "com.apple.dt.Xcode",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.sublimetext.4",
        "com.jetbrains.intellij",

        // MacShield itself
        "com.macshield.app",
    ]

    private var panicHotKey: HotKey?

    private init() {
        setupPanicKey()
    }

    // MARK: - Panic Key

    private func setupPanicKey() {
        // Cmd + Option + Shift + Control + U
        panicHotKey = HotKey(
            key: .u,
            modifiers: [.command, .option, .shift, .control]
        )

        panicHotKey?.keyDownHandler = { [weak self] in
            self?.triggerPanic()
        }
    }

    private func triggerPanic() {
        NSLog("[MacShield Safety] Panic key activated — dismissing all overlays")
        onPanicKeyPressed?()
    }

    // MARK: - Blacklist

    /// Check whether an app is on the system blacklist and must never be locked.
    static func isBlacklisted(_ bundleIdentifier: String) -> Bool {
        return systemBlacklist.contains(bundleIdentifier)
    }
}

// MARK: - Single-Instance Guard

extension SafetyManager {
    /// Pure rule: a newly launched instance yields (exits) if an OLDER instance
    /// (lower pid) is already running. Deterministic so two simultaneous launches
    /// never both quit.
    /// ponytail: pids effectively only increase between two near-simultaneous launches;
    /// pid wraparound (after ~99999) could in theory pick the wrong winner — acceptable.
    static func shouldYieldToOlderInstance(myPid: Int32, otherPids: [Int32]) -> Bool {
        otherPids.contains { $0 < myPid }
    }

    /// Whether THIS instance should exit because another MacShield is already running.
    /// Prevents duplicate menu-bar icons / overlays when both the login item and the
    /// keep-alive agent try to launch the app.
    static func shouldExitAsDuplicate() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.macshield.app"
        let mine = ProcessInfo.processInfo.processIdentifier
        let otherPids = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated && $0.processIdentifier != mine }
            .map { $0.processIdentifier }
        return shouldYieldToOlderInstance(myPid: mine, otherPids: otherPids)
    }
}

#if !APP_STORE
// MARK: - Tamper Resistance (auto-relaunch if force-quit)
//
// A per-user launchd LaunchAgent relaunches MacShield after an abnormal exit
// (force-quit from Activity Monitor, `kill`, or a crash). A clean Quit from the
// authenticated menu exits with status 0 and is intentionally NOT relaunched.
//
// HONEST LIMITS (cannot be fixed by any unsandboxed userland app):
// - SIGKILL itself cannot be blocked; we can only relaunch afterwards.
// - `root`, `launchctl bootout`, or toggling the item off in System Settings ›
//   Login Items can still stop it. This raises the bar against a casual
//   "Force Quit in Activity Monitor", it does not make the process unkillable.
// Not available in the sandboxed App Store build (no LaunchAgents / launchctl access).

extension SafetyManager {
    /// launchd label for the keep-alive agent.
    static let keepAliveLabel = "com.macshield.keepalive"

    private static var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private static var keepAlivePlistURL: URL {
        launchAgentsDir.appendingPathComponent("\(keepAliveLabel).plist")
    }

    /// Whether the keep-alive agent plist is installed on disk.
    static var isKeepAliveInstalled: Bool {
        FileManager.default.fileExists(atPath: keepAlivePlistURL.path)
    }

    /// The LaunchAgent property list.
    ///
    /// `KeepAlive = { SuccessfulExit = false }`: relaunch ONLY after a non-zero / signal
    /// exit (force-quit, kill, crash). A clean Quit (exit 0) is left dead until next login.
    static func keepAlivePlist(executablePath: String) -> [String: Any] {
        [
            "Label": keepAliveLabel,
            "ProgramArguments": [executablePath],
            "KeepAlive": ["SuccessfulExit": false],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]
    }

    /// Serialized XML plist data (also used by the build-time self-check).
    static func keepAlivePlistData(executablePath: String) -> Data? {
        try? PropertyListSerialization.data(
            fromPropertyList: keepAlivePlist(executablePath: executablePath),
            format: .xml,
            options: 0
        )
    }

    /// Install and load the keep-alive agent. Returns true if the plist was written.
    @discardableResult
    static func enableKeepAlive() -> Bool {
        guard let exe = Bundle.main.executableURL?.path,
              let data = keepAlivePlistData(executablePath: exe) else { return false }
        do {
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            try data.write(to: keepAlivePlistURL, options: .atomic)
        } catch {
            NSLog("[MacShield] Failed to write keep-alive agent: %@", error.localizedDescription)
            return false
        }
        // Refresh: bootout (ignore failure if not loaded) then bootstrap.
        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(keepAliveLabel)"])
        let loaded = runLaunchctl(["bootstrap", "gui/\(uid)", keepAlivePlistURL.path])
        NSLog("[MacShield] Keep-alive agent installed (loaded=%@)", loaded ? "yes" : "deferred")
        return true
    }

    /// Unload and remove the keep-alive agent.
    @discardableResult
    static func disableKeepAlive() -> Bool {
        let uid = getuid()
        _ = runLaunchctl(["bootout", "gui/\(uid)/\(keepAliveLabel)"])
        try? FileManager.default.removeItem(at: keepAlivePlistURL)
        NSLog("[MacShield] Keep-alive agent removed")
        return true
    }

    /// Reconcile the installed agent with the desired state (called at launch).
    /// Re-asserting when enabled also repairs a stale executable path after an app move/update.
    static func syncKeepAlive(enabled: Bool) {
        if enabled {
            enableKeepAlive()
        } else if isKeepAliveInstalled {
            disableKeepAlive()
        }
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            NSLog("[MacShield] launchctl %@ failed: %@", args.first ?? "", error.localizedDescription)
            return false
        }
    }
}
#endif
