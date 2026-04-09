import AppKit

/// Manages blur overlay windows — one per blurred app window.
///
/// Each overlay is a borderless, transparent NSPanel positioned over the
/// target app's **content area** (inset from sidebar, toolbar, etc.).
/// Clicks pass through to the app beneath (ignoresMouseEvents = true).
///
/// Content-area blurring:
/// - Each BlurredApp carries ContentInsets (top, left, bottom, right).
/// - The overlay panel is sized to cover only the region INSIDE those insets,
///   so the sidebar, toolbar, and window chrome remain fully visible.
///
/// Background blur prevention:
/// - Overlays are removed on app deactivation via BlurOverlayService.
/// - As a safety net, the refresh timer also removes overlays whose
///   owner app is no longer frontmost.
final class BlurWindowManager {
    static let shared = BlurWindowManager()

    /// Active overlay windows keyed by target app PID.
    private(set) var overlayWindows: [pid_t: NSPanel] = [:]

    /// Active blur content views keyed by target app PID.
    private(set) var blurViews: [pid_t: BlurContentView] = [:]

    /// Cached running app references for position polling.
    private var trackedApps: [pid_t: NSRunningApplication] = [:]

    /// Stored content insets per PID, used on every reposition.
    private var contentInsets: [pid_t: BlurredApp.ContentInsets] = [:]

    /// Refresh timer for continuous overlay position + reveal updates.
    private var refreshTimer: Timer?

    /// Global mouse-event monitor (for reveal zone tracking).
    private var mouseMonitor: Any?

    /// Local mouse-event monitor (if our app becomes active).
    private var localMouseMonitor: Any?

    /// Last known mouse position, used for throttled event-monitor updates.
    private var lastMouseLocation: NSPoint = .zero

    /// Minimum cursor displacement (points) before the event monitor fires an extra update.
    private let cursorMoveThreshold: CGFloat = 2.0

    /// Window level: one below .screenSaver (1000) — above all normal apps and floating panels.
    private let overlayWindowLevel = NSWindow.Level(rawValue: 999)

    private init() {}

    // MARK: - Create / Update Overlays

    /// Create a blur overlay for the given app's content area.
    ///
    /// - Parameters:
    ///   - app: The running application to blur.
    ///   - settings: Global blur settings (intensity, reveal, feather, etc.).
    ///   - insets: Content insets that restrict the blur to the chat area only.
    func createOverlay(
        for app: NSRunningApplication,
        settings: AppSettings,
        insets: BlurredApp.ContentInsets = .none
    ) -> NSPanel? {
        let pid = app.processIdentifier

        // Don't create duplicate overlays
        if overlayWindows[pid] != nil {
            updateOverlayPosition(for: app)
            return overlayWindows[pid]
        }

        // Get the full window frame first
        guard let fullFrame = WindowTracker.shared.getBoundingFrame(for: app)
                ?? WindowTracker.shared.getWindowFrame(for: app) else {
            NSLog("[MacShield] Cannot get window frame for %@", app.bundleIdentifier ?? "unknown")
            return nil
        }

        // Apply content insets to only blur the chat area
        let contentFrame = applyInsets(insets, to: fullFrame)
        let appKitFrame = convertToAppKitCoordinates(contentFrame)

        let panel = NSPanel(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = overlayWindowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // CRITICAL: click-through so the user can interact with the app beneath
        panel.ignoresMouseEvents = true

        let blurView = BlurContentView(frame: NSRect(origin: .zero, size: appKitFrame.size))
        blurView.blurRadius    = CGFloat(settings.blurIntensity)
        blurView.revealRadius  = CGFloat(settings.revealRadius)
        blurView.revealOnHover = settings.revealOnHover
        blurView.featherWidth  = CGFloat(settings.blurFeatherWidth)
        blurView.autoresizingMask = [.width, .height]

        panel.contentView = blurView

        // Fade in (skip animation when Reduce Motion is on)
        if settings.blurAnimatesIn && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFront(nil)
        }

        overlayWindows[pid] = panel
        blurViews[pid] = blurView
        trackedApps[pid] = app
        self.contentInsets[pid] = insets

        // Observe AX window move/resize
        WindowTracker.shared.observeWindowChanges(for: app) { [weak self] newFrame in
            guard let self else { return }
            let insetFrame = self.applyInsets(insets, to: newFrame)
            self.repositionOverlay(pid: pid, to: insetFrame)
        }

        startMouseMonitoring()
        startRefreshTimer()

        // Delayed re-query for Catalyst apps
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.syncOverlayPosition(pid: pid)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.syncOverlayPosition(pid: pid)
        }

        NSLog("[MacShield] Blur overlay created for %@ (pid %d) insets=L%.0f/T%.0f/R%.0f/B%.0f",
              app.localizedName ?? "unknown", pid,
              insets.left, insets.top, insets.right, insets.bottom)
        return panel
    }

    /// Update blur settings on all active overlays.
    func updateSettings(_ settings: AppSettings) {
        for (_, blurView) in blurViews {
            blurView.blurRadius    = CGFloat(settings.blurIntensity)
            blurView.revealRadius  = CGFloat(settings.revealRadius)
            blurView.revealOnHover = settings.revealOnHover
            blurView.featherWidth  = CGFloat(settings.blurFeatherWidth)
        }
    }

    /// Update overlay position to match target window.
    func updateOverlayPosition(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        syncOverlayPosition(pid: pid)
    }

    /// Remove the overlay for a specific app, with a fade-out.
    func removeOverlay(for pid: pid_t) {
        guard let panel = overlayWindows[pid] else { return }

        overlayWindows.removeValue(forKey: pid)
        blurViews.removeValue(forKey: pid)
        trackedApps.removeValue(forKey: pid)
        contentInsets.removeValue(forKey: pid)
        WindowTracker.shared.stopObserving(pid: pid)
        NSLog("[MacShield] Blur overlay removed for pid %d", pid)

        // Fade out then close
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.close()
            })
        } else {
            panel.close()
        }

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
    var isShowingAny: Bool { !overlayWindows.isEmpty }

    // MARK: - Content Insets

    /// Shrink a window frame by the given insets to get the content-only area.
    /// Coordinates are in Accessibility space (top-left origin).
    private func applyInsets(_ insets: BlurredApp.ContentInsets, to frame: CGRect) -> CGRect {
        let x = frame.origin.x + insets.left
        let y = frame.origin.y + insets.top
        let w = max(0, frame.width - insets.left - insets.right)
        let h = max(0, frame.height - insets.top - insets.bottom)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Private Repositioning

    /// Re-query the current frame for a tracked app and reposition the overlay.
    private func syncOverlayPosition(pid: pid_t) {
        guard let panel = overlayWindows[pid],
              let app = trackedApps[pid] else { return }

        guard let fullFrame = WindowTracker.shared.getBoundingFrame(for: app)
                ?? WindowTracker.shared.getWindowFrame(for: app) else { return }

        let insets = contentInsets[pid] ?? .none
        let contentFrame = applyInsets(insets, to: fullFrame)
        let appKitFrame = convertToAppKitCoordinates(contentFrame)
        if panel.frame != appKitFrame {
            panel.setFrame(appKitFrame, display: false)
        }
    }

    private func repositionOverlay(pid: pid_t, to accessibilityFrame: CGRect) {
        guard let panel = overlayWindows[pid] else { return }
        let appKitFrame = convertToAppKitCoordinates(accessibilityFrame)
        panel.setFrame(appKitFrame, display: false)
    }

    /// Convert from Accessibility (top-left origin) to AppKit (bottom-left origin) coordinates.
    private func convertToAppKitCoordinates(_ rect: CGRect) -> NSRect {
        guard let screen = NSScreen.screens.first else { return NSRect(origin: .zero, size: rect.size) }
        let screenHeight = screen.frame.height
        let flippedY = screenHeight - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }

    // MARK: - Mouse Tracking

    private func startMouseMonitoring() {
        guard mouseMonitor == nil else { return }

        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp]

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func stopMouseMonitoring() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    /// Event-driven mouse handler with 2pt threshold for continuous moves, instant for clicks.
    private func handleMouseEvent(_ event: NSEvent) {
        let current = NSEvent.mouseLocation
        
        if event.type == .leftMouseDown || event.type == .leftMouseUp {
            lastMouseLocation = current
            updateRevealPositions(mouseLocation: current)
            return
        }

        let dx = current.x - lastMouseLocation.x
        let dy = current.y - lastMouseLocation.y
        guard (dx * dx + dy * dy) >= (cursorMoveThreshold * cursorMoveThreshold) else { return }
        lastMouseLocation = current
        updateRevealPositions(mouseLocation: current)
    }

    /// Push current mouse location into every active blur view.
    private func updateRevealPositions(mouseLocation: NSPoint? = nil) {
        let location = mouseLocation ?? NSEvent.mouseLocation
        let isLeftMouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        
        for (_, blurView) in blurViews {
            if blurView.revealOnHover {
                blurView.updateRevealFromScreenPoint(location)
            } else {
                if isLeftMouseDown {
                    blurView.updateRevealFromScreenPoint(location)
                } else {
                    blurView.revealCenter = nil
                }
            }
        }
    }

    // MARK: - Refresh Timer

    /// Position-sync + reveal-update timer at 30fps.
    ///
    /// Also acts as a safety net: removes overlays whose owner app
    /// is no longer frontmost (fixes background blur sticking).
    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

            // 1. Sync overlay positions & remove stale overlays
            for pid in Array(self.overlayWindows.keys) {
                // Safety net: if the app is no longer frontmost, remove its overlay.
                // This catches cases where the deactivation notification was missed
                // (common with Catalyst/Electron apps).
                if pid != frontmostPID {
                    NSLog("[MacShield] Timer safety: removing overlay for non-frontmost pid %d", pid)
                    self.removeOverlay(for: pid)
                    continue
                }
                self.syncOverlayPosition(pid: pid)
            }

            // 2. Update reveal positions
            self.updateRevealPositions()
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
