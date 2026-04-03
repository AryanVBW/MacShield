import AppKit

/// Manages blur overlay windows — one per blurred app window.
/// Each overlay is a borderless, transparent NSPanel positioned
/// exactly over the target app's window. Click-through so users
/// can interact with the app normally while the blur is active.
final class BlurWindowManager {
    static let shared = BlurWindowManager()

    /// Active overlay windows keyed by target app PID.
    private(set) var overlayWindows: [pid_t: NSPanel] = [:]

    /// Active blur content views keyed by target app PID.
    private(set) var blurViews: [pid_t: BlurContentView] = [:]

    /// Refresh timer for continuous reveal-zone updates.
    private var refreshTimer: Timer?

    /// Global mouse-event monitor (for reveal zone tracking).
    private var mouseMonitor: Any?

    private init() {}

    // MARK: - Create / Update Overlays

    /// Create a blur overlay for the given app's window.
    func createOverlay(for app: NSRunningApplication, settings: AppSettings) -> NSPanel? {
        let pid = app.processIdentifier

        // Don't create duplicate overlays
        if overlayWindows[pid] != nil {
            updateOverlayPosition(for: app)
            return overlayWindows[pid]
        }

        guard let targetFrame = WindowTracker.shared.getWindowFrame(for: app) else {
            NSLog("[MacShield] Cannot get window frame for %@", app.bundleIdentifier ?? "unknown")
            return nil
        }

        // Convert Accessibility coordinates (top-left origin) to AppKit coordinates (bottom-left origin)
        let appKitFrame = convertToAppKitCoordinates(targetFrame)

        let panel = NSPanel(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // CRITICAL: click-through so the user can interact with the app beneath
        panel.ignoresMouseEvents = true

        let blurView = BlurContentView(frame: NSRect(origin: .zero, size: appKitFrame.size))
        blurView.blurRadius = CGFloat(settings.blurIntensity)
        blurView.revealRadius = CGFloat(settings.revealRadius)
        blurView.revealOnHover = settings.revealOnHover
        blurView.autoresizingMask = [.width, .height]

        panel.contentView = blurView
        panel.orderFront(nil)

        overlayWindows[pid] = panel
        blurViews[pid] = blurView

        // Observe window move/resize
        WindowTracker.shared.observeWindowChanges(for: app) { [weak self] newFrame in
            self?.repositionOverlay(pid: pid, to: newFrame)
        }

        // Start mouse tracking and refresh timer if not already running
        startMouseMonitoring()
        startRefreshTimer()

        NSLog("[MacShield] Blur overlay created for %@ (pid %d)", app.localizedName ?? "unknown", pid)
        return panel
    }

    /// Update blur settings on all active overlays.
    func updateSettings(_ settings: AppSettings) {
        for (_, blurView) in blurViews {
            blurView.blurRadius = CGFloat(settings.blurIntensity)
            blurView.revealRadius = CGFloat(settings.revealRadius)
            blurView.revealOnHover = settings.revealOnHover
        }
    }

    /// Update overlay position to match target window.
    func updateOverlayPosition(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard let targetFrame = WindowTracker.shared.getWindowFrame(for: app) else { return }
        repositionOverlay(pid: pid, to: targetFrame)
    }

    /// Remove the overlay for a specific app.
    func removeOverlay(for pid: pid_t) {
        overlayWindows[pid]?.close()
        overlayWindows.removeValue(forKey: pid)
        blurViews.removeValue(forKey: pid)
        WindowTracker.shared.stopObserving(pid: pid)
        NSLog("[MacShield] Blur overlay removed for pid %d", pid)

        if overlayWindows.isEmpty {
            stopRefreshTimer()
            stopMouseMonitoring()
        }
    }

    /// Remove all blur overlays.
    func removeAll() {
        let pids = Array(overlayWindows.keys)
        for pid in pids {
            removeOverlay(for: pid)
        }
        WindowTracker.shared.stopAll()
        stopRefreshTimer()
        stopMouseMonitoring()
        NSLog("[MacShield] All blur overlays removed")
    }

    /// Whether any blur overlay is currently shown.
    var isShowingAny: Bool {
        !overlayWindows.isEmpty
    }

    // MARK: - Private

    private func repositionOverlay(pid: pid_t, to accessibilityFrame: CGRect) {
        guard let panel = overlayWindows[pid] else { return }
        let appKitFrame = convertToAppKitCoordinates(accessibilityFrame)
        panel.setFrame(appKitFrame, display: true)
    }

    /// Convert from Accessibility (top-left origin) to AppKit (bottom-left origin) coordinates.
    private func convertToAppKitCoordinates(_ rect: CGRect) -> NSRect {
        guard let screen = NSScreen.screens.first else { return NSRect(origin: .zero, size: rect.size) }
        let screenHeight = screen.frame.height
        let flippedY = screenHeight - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }

    // MARK: - Mouse Tracking

    /// Install a global mouse-moved monitor to track the cursor
    /// and update reveal zones on all active blur views.
    private func startMouseMonitoring() {
        guard mouseMonitor == nil else { return }

        // Use addGlobalMonitorForEvents to track mouse even when our overlay
        // doesn't receive events (ignoresMouseEvents = true).
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            self?.updateRevealPositions()
        }
    }

    private func stopMouseMonitoring() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    /// Push current mouse location into every active blur view.
    private func updateRevealPositions() {
        let mouseLocation = NSEvent.mouseLocation  // screen coordinates
        for (_, blurView) in blurViews {
            if blurView.revealOnHover {
                blurView.updateRevealFromScreenPoint(mouseLocation)
            }
        }
    }

    // MARK: - Refresh Timer

    /// Refresh timer to keep overlay positions and reveal zones up-to-date.
    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateRevealPositions()
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
