import AppKit

/// Manages blur overlay windows for MacShield.
///
/// Supports two blur modes:
///
/// **Full Chat Area (`.fullChatArea`):**
///   One `NSPanel` overlay per target app, covering the inset content area.
///   (Original behaviour — always active as fallback.)
///
/// **Per-Message Bubble (`.perMessageBubble`):**
///   Uses `MessageBubbleScanner` to find individual message row frames via the
///   Accessibility API, then creates one small `NSPanel` per bubble.
///   Falls back to full-area mode if the scanner returns 0 frames.
///
/// Clicks always pass through to the app beneath (`ignoresMouseEvents = true`).
final class BlurWindowManager {
    static let shared = BlurWindowManager()

    // MARK: - State

    /// Active full-area overlay windows keyed by target app PID.
    private(set) var overlayWindows: [pid_t: NSPanel] = [:]

    /// Blur content views for full-area overlays.
    private(set) var blurViews: [pid_t: BlurContentView] = [:]

    /// Per-bubble overlay pool keyed by target app PID.
    /// Each PID maps to an array of (panel, blurView) pairs.
    private var bubblePanels: [pid_t: [(NSPanel, BlurContentView)]] = [:]

    /// Cached running app references for position polling.
    private var trackedApps: [pid_t: NSRunningApplication] = [:]

    /// Stored content insets per PID, used on every reposition.
    private var contentInsets: [pid_t: BlurredApp.ContentInsets] = [:]

    /// Blur mode per PID.
    private var blurModes: [pid_t: BlurMode] = [:]

    /// Bundle ID per PID (needed for the scanner).
    private var bundleIDs: [pid_t: String] = [:]

    /// Latest app settings (blur radius, reveal, etc.)
    private var latestSettings: AppSettings?

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

    /// Counter used to throttle AX scans (scan every 4th timer tick ≈ 7 fps).
    private var timerTickCount: Int = 0

    /// Window level: one below .screenSaver (1000) — above all normal apps and floating panels.
    private let overlayWindowLevel = NSWindow.Level(rawValue: 999)

    private init() {}

    // MARK: - Create / Update Overlays

    /// Create a blur overlay (full-area or per-bubble) for the given app.
    func createOverlay(
        for app: NSRunningApplication,
        settings: AppSettings,
        insets: BlurredApp.ContentInsets = .none,
        blurMode: BlurMode = .perMessageBubble
    ) -> NSPanel? {
        let pid = app.processIdentifier

        // Don't create duplicate overlays
        if overlayWindows[pid] != nil || bubblePanels[pid] != nil {
            updateOverlayPosition(for: app)
            return overlayWindows[pid]
        }

        latestSettings = settings
        trackedApps[pid] = app
        contentInsets[pid] = insets
        blurModes[pid] = blurMode
        bundleIDs[pid] = app.bundleIdentifier ?? ""

        if blurMode == .perMessageBubble {
            // Attempt bubble scan; fall back to full-area if empty
            let frames = MessageBubbleScanner.shared.scan(pid: pid, bundleID: app.bundleIdentifier ?? "")
            if !frames.isEmpty {
                applyBubbleOverlays(pid: pid, frames: frames, settings: settings, animate: true)
                NSLog("[MacShield] Bubble overlay created for %@ (pid %d) — %d bubbles",
                      app.localizedName ?? "?", pid, frames.count)
            } else {
                NSLog("[MacShield] Bubble scan returned 0 frames for %@ — falling back to full-area", app.localizedName ?? "?")
                return createFullAreaOverlay(for: app, settings: settings, insets: insets)
            }
        } else {
            return createFullAreaOverlay(for: app, settings: settings, insets: insets)
        }

        // Observe AX window move/resize to trigger a re-scan
        WindowTracker.shared.observeWindowChanges(for: app) { [weak self] _ in
            self?.syncBubbleOverlays(pid: pid)
        }

        startMouseMonitoring()
        startRefreshTimer()

        return nil
    }

    // MARK: - Full-Area Overlay (Private)

    @discardableResult
    private func createFullAreaOverlay(
        for app: NSRunningApplication,
        settings: AppSettings,
        insets: BlurredApp.ContentInsets
    ) -> NSPanel? {
        let pid = app.processIdentifier

        guard let fullFrame = WindowTracker.shared.getBoundingFrame(for: app)
                ?? WindowTracker.shared.getWindowFrame(for: app) else {
            NSLog("[MacShield] Cannot get window frame for %@", app.bundleIdentifier ?? "unknown")
            return nil
        }

        let contentFrame = applyInsets(insets, to: fullFrame)
        let panel = makeBlurPanel(frame: convertToAppKitCoordinates(contentFrame), settings: settings)
        let blurView = panel.contentView as! BlurContentView

        showPanel(panel, animated: settings.blurAnimatesIn)

        overlayWindows[pid] = panel
        blurViews[pid] = blurView

        WindowTracker.shared.observeWindowChanges(for: app) { [weak self] newFrame in
            guard let self else { return }
            let insetFrame = self.applyInsets(insets, to: newFrame)
            self.repositionOverlay(pid: pid, to: insetFrame)
        }

        startMouseMonitoring()
        startRefreshTimer()

        // Delayed re-query for Catalyst apps
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.syncOverlayPosition(pid: pid) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6)  { [weak self] in self?.syncOverlayPosition(pid: pid) }

        NSLog("[MacShield] Full-area overlay created for %@ (pid %d)", app.localizedName ?? "?", pid)
        return panel
    }

    // MARK: - Bubble Panel Pool

    /// Reconcile the bubble panel pool for `pid` to match `frames`.
    ///  - New frames → new panels created.
    ///  - Existing frames → panels repositioned.
    ///  - Extra panels → removed.
    private func applyBubbleOverlays(pid: pid_t, frames: [CGRect], settings: AppSettings, animate: Bool = false) {
        var existing = bubblePanels[pid] ?? []

        // Grow pool if we need more panels
        while existing.count < frames.count {
            let panel = makeBlurPanel(frame: .zero, settings: settings)
            let view = panel.contentView as! BlurContentView
            // In bubble mode, reveal = hide the entire panel (no partial reveal)
            view.revealCenter = nil
            existing.append((panel, view))
        }

        // Shrink pool if we have too many
        while existing.count > frames.count {
            let (panel, _) = existing.removeLast()
            panel.close()
        }

        // Position and show each panel
        for (index, frame) in frames.enumerated() {
            let (panel, _) = existing[index]
            let appKitFrame = convertToAppKitCoordinates(frame)

            if panel.frame != appKitFrame {
                panel.setFrame(appKitFrame, display: false)
            }
            if !panel.isVisible {
                if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    panel.alphaValue = 0
                    panel.orderFront(nil)
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.15
                        panel.animator().alphaValue = 1
                    }
                } else {
                    panel.orderFront(nil)
                }
            }
        }

        bubblePanels[pid] = existing
    }

    /// Re-scan message bubbles for `pid` and reconcile the panel pool.
    private func syncBubbleOverlays(pid: pid_t) {
        guard let app = trackedApps[pid],
              blurModes[pid] == .perMessageBubble,
              let settings = latestSettings else { return }

        let bundleID = bundleIDs[pid] ?? ""
        let frames = MessageBubbleScanner.shared.scan(pid: pid, bundleID: bundleID)

        if frames.isEmpty {
            // Fall back to full-area if scan is empty (conversation switched / app updated)
            removeAllBubblePanels(pid: pid)
            if overlayWindows[pid] == nil {
                createFullAreaOverlay(for: app, settings: settings, insets: contentInsets[pid] ?? .none)
            }
        } else {
            // Remove full-area fallback if it was created
            if let panel = overlayWindows[pid] {
                panel.close()
                overlayWindows.removeValue(forKey: pid)
                blurViews.removeValue(forKey: pid)
            }
            applyBubbleOverlays(pid: pid, frames: frames, settings: settings)
        }
    }

    private func removeAllBubblePanels(pid: pid_t) {
        guard let panels = bubblePanels.removeValue(forKey: pid) else { return }
        for (panel, _) in panels { panel.close() }
    }

    // MARK: - Shared Panel Factory

    /// Creates a borderless, click-through `NSPanel` with a `BlurContentView` as content.
    private func makeBlurPanel(frame: NSRect, settings: AppSettings) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
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
        panel.ignoresMouseEvents = true

        let blurView = BlurContentView(frame: NSRect(origin: .zero, size: frame.size))
        blurView.blurRadius    = CGFloat(settings.blurIntensity)
        blurView.revealRadius  = CGFloat(settings.revealRadius)
        blurView.revealOnHover = settings.revealOnHover
        blurView.featherWidth  = CGFloat(settings.blurFeatherWidth)
        blurView.autoresizingMask = [.width, .height]
        panel.contentView = blurView

        return panel
    }

    private func showPanel(_ panel: NSPanel, animated: Bool) {
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
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
    }

    // MARK: - Settings Update

    /// Update blur settings on all active overlays (full-area and bubble panels).
    func updateSettings(_ settings: AppSettings) {
        latestSettings = settings

        for (_, blurView) in blurViews {
            applySettings(settings, to: blurView)
        }
        for (_, pairs) in bubblePanels {
            for (_, blurView) in pairs {
                applySettings(settings, to: blurView)
            }
        }
    }

    private func applySettings(_ settings: AppSettings, to view: BlurContentView) {
        view.blurRadius    = CGFloat(settings.blurIntensity)
        view.revealRadius  = CGFloat(settings.revealRadius)
        view.revealOnHover = settings.revealOnHover
        view.featherWidth  = CGFloat(settings.blurFeatherWidth)
    }

    // MARK: - Position Updates (Full-Area)

    func updateOverlayPosition(for app: NSRunningApplication) {
        syncOverlayPosition(pid: app.processIdentifier)
    }

    private func syncOverlayPosition(pid: pid_t) {
        guard let panel = overlayWindows[pid],
              let app = trackedApps[pid] else { return }

        guard let fullFrame = WindowTracker.shared.getBoundingFrame(for: app)
                ?? WindowTracker.shared.getWindowFrame(for: app) else { return }

        let insets = contentInsets[pid] ?? .none
        let contentFrame = applyInsets(insets, to: fullFrame)
        let appKitFrame = convertToAppKitCoordinates(contentFrame)
        if panel.frame != appKitFrame { panel.setFrame(appKitFrame, display: false) }
    }

    private func repositionOverlay(pid: pid_t, to accessibilityFrame: CGRect) {
        guard let panel = overlayWindows[pid] else { return }
        panel.setFrame(convertToAppKitCoordinates(accessibilityFrame), display: false)
    }

    // MARK: - Remove Overlays

    /// Remove all overlays (full-area + bubble) for a specific app.
    func removeOverlay(for pid: pid_t) {
        // Remove full-area overlay
        if let panel = overlayWindows.removeValue(forKey: pid) {
            blurViews.removeValue(forKey: pid)
            fadeAndClose(panel)
        }
        // Remove bubble panels
        removeAllBubblePanels(pid: pid)

        trackedApps.removeValue(forKey: pid)
        contentInsets.removeValue(forKey: pid)
        blurModes.removeValue(forKey: pid)
        bundleIDs.removeValue(forKey: pid)
        WindowTracker.shared.stopObserving(pid: pid)
        NSLog("[MacShield] Overlay removed for pid %d", pid)

        if overlayWindows.isEmpty && bubblePanels.isEmpty {
            stopRefreshTimer()
            stopMouseMonitoring()
        }
    }

    private func fadeAndClose(_ panel: NSPanel) {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.close() })
        } else {
            panel.close()
        }
    }

    /// Remove all overlays for all apps.
    func removeAll() {
        let pids = Array(trackedApps.keys)
        pids.forEach { removeOverlay(for: $0) }
        WindowTracker.shared.stopAll()
        stopRefreshTimer()
        stopMouseMonitoring()
        NSLog("[MacShield] All overlays removed")
    }

    var isShowingAny: Bool {
        !overlayWindows.isEmpty || !bubblePanels.isEmpty
    }

    // MARK: - Content Insets

    private func applyInsets(_ insets: BlurredApp.ContentInsets, to frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x + insets.left,
            y: frame.origin.y + insets.top,
            width: max(0, frame.width  - insets.left - insets.right),
            height: max(0, frame.height - insets.top  - insets.bottom)
        )
    }

    // MARK: - Coordinate Conversion

    /// Convert from Accessibility (top-left origin) to AppKit (bottom-left origin) coordinates.
    func convertToAppKitCoordinates(_ rect: CGRect) -> NSRect {
        guard let screen = NSScreen.screens.first else { return NSRect(origin: .zero, size: rect.size) }
        let flippedY = screen.frame.height - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }

    // MARK: - Mouse Tracking

    private func startMouseMonitoring() {
        guard mouseMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp]
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMouseEvent(event)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func stopMouseMonitoring() {
        if let m = mouseMonitor  { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
    }

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

    /// Push the current mouse reveal position to all full-area blur views.
    /// Bubble panels reveal by toggling the panel's alpha (handled in the timer).
    private func updateRevealPositions(mouseLocation: NSPoint? = nil) {
        let location = mouseLocation ?? NSEvent.mouseLocation
        let isLeftDown = (NSEvent.pressedMouseButtons & 1) != 0

        // Full-area views — radial reveal
        for (_, blurView) in blurViews {
            if blurView.revealOnHover {
                blurView.updateRevealFromScreenPoint(location)
            } else {
                blurView.revealCenter = isLeftDown ? {
                    blurView.updateRevealFromScreenPoint(location)
                    return blurView.revealCenter
                }() : nil
            }
        }

        // Bubble panels — hide the panel whose frame contains the cursor
        for (_, pairs) in bubblePanels {
            for (panel, blurView) in pairs {
                let panelContainsCursor = panel.frame.contains(location)
                let shouldReveal: Bool
                if blurView.revealOnHover {
                    shouldReveal = panelContainsCursor
                } else {
                    shouldReveal = panelContainsCursor && isLeftDown
                }
                // Reveal = make panel invisible (show the real message underneath)
                let targetAlpha: CGFloat = shouldReveal ? 0.0 : 1.0
                if panel.alphaValue != targetAlpha {
                    panel.alphaValue = targetAlpha
                }
            }
        }
    }

    // MARK: - Refresh Timer

    /// 30 fps position-sync timer.
    /// Every 4th tick (~7 fps) also re-scans message bubbles.
    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            self.timerTickCount &+= 1
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

            for pid in Array(self.trackedApps.keys) {
                // Safety net: if the app is no longer frontmost, remove its overlay.
                if pid != frontmostPID {
                    NSLog("[MacShield] Timer safety: removing stale overlay for pid %d", pid)
                    self.removeOverlay(for: pid)
                    continue
                }

                // Sync full-area overlay position
                self.syncOverlayPosition(pid: pid)

                // Re-scan bubble positions every 4th tick
                if self.timerTickCount % 4 == 0,
                   self.blurModes[pid] == .perMessageBubble {
                    self.syncBubbleOverlays(pid: pid)
                }
            }

            // Update reveal zones
            self.updateRevealPositions()
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
