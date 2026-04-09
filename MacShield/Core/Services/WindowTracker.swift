import ApplicationServices
import AppKit

/// Tracks target app windows via the Accessibility API.
/// Provides window frame queries and move/resize observation.
///
/// WhatsApp / Catalyst compatibility notes:
/// - WhatsApp (Catalyst) reports its main window as `subrole=AXDialog`
///   with `isMain=false`. We treat AXDialog as a valid main-window candidate.
/// - AXDialog windows may not fire kAXMovedNotification / kAXResizedNotification
///   reliably during Catalyst animations. The caller (BlurWindowManager) compensates
///   with a higher-frequency polling timer.
/// - WhatsApp creates multiple CGWindows (toolbar bands, tooltips) but exposes
///   only 1 AXWindow. We always target that single AX window for observation.
final class WindowTracker {
    static let shared = WindowTracker()

    private var observers: [pid_t: AXObserver] = [:]
    private var callbacks: [pid_t: (CGRect) -> Void] = [:]

    private init() {}

    // MARK: - Window Frame

    /// Get the frame of the main (largest) window for the given app.
    ///
    /// Detection order:
    /// 1. Window with `kAXMainAttribute == true`
    /// 2. Window with `subrole == AXStandardWindow` or `AXDialog` (Catalyst apps)
    /// 3. Largest window by area (≥ 100×100)
    /// 4. First window as final fallback
    func getWindowFrame(for app: NSRunningApplication) -> CGRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else { return nil }

        // 1. Prefer the window that reports isMain == true
        for window in windows {
            var mainRef: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef)
            if let isMain = mainRef as? Bool, isMain {
                return frameForElement(window)
            }
        }

        // 2. Look for AXStandardWindow or AXDialog subrole (catches WhatsApp/Catalyst)
        for window in windows {
            var subroleRef: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
            if let subrole = subroleRef as? String,
               (subrole == "AXStandardWindow" || subrole == "AXDialog") {
                if let frame = frameForElement(window), frame.width >= 100, frame.height >= 100 {
                    return frame
                }
            }
        }

        // 3. Fall back to the largest window by area
        var bestFrame: CGRect? = nil
        var bestArea: CGFloat = 0
        for window in windows {
            guard let frame = frameForElement(window) else { continue }
            if frame.width < 100 || frame.height < 100 { continue }
            let area = frame.width * frame.height
            if area > bestArea {
                bestArea = area
                bestFrame = frame
            }
        }

        // 4. Final fallback: first window with any frame
        return bestFrame ?? frameForElement(windows[0])
    }

    /// Get a bounding rect that covers ALL visible windows for the app.
    /// Useful for Catalyst/Electron apps that create multiple overlapping windows.
    func getBoundingFrame(for app: NSRunningApplication) -> CGRect? {
        let pid = app.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var union: CGRect? = nil
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w >= 50, h >= 50 else { continue }

            let rect = CGRect(x: x, y: y, width: w, height: h)
            union = union?.union(rect) ?? rect
        }
        return union
    }

    /// Get frames of ALL windows for the given app.
    func getAllWindowFrames(for app: NSRunningApplication) -> [(AXUIElement, CGRect)] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else { return [] }

        return windows.compactMap { window in
            guard let frame = frameForElement(window) else { return nil }
            return (window, frame)
        }
    }

    // MARK: - Observation

    /// Observe window move/resize for the given app.
    ///
    /// For Catalyst apps (like WhatsApp) whose window is an AXDialog,
    /// we observe all available notifications. The BlurWindowManager also
    /// runs a polling timer as a safety net for apps that don't fire reliably.
    func observeWindowChanges(for app: NSRunningApplication, callback: @escaping (CGRect) -> Void) {
        let pid = app.processIdentifier
        callbacks[pid] = callback
        stopObserving(pid: pid)

        var observer: AXObserver?
        let result = AXObserverCreate(pid, windowChangeCallback, &observer)
        guard result == .success, let obs = observer else {
            NSLog("[MacShield] Failed to create AXObserver for pid %d", pid)
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        if let windows = windowsRef as? [AXUIElement] {
            let targetWindow = findTargetWindow(from: windows)

            if let window = targetWindow {
                let selfPtr = Unmanaged.passUnretained(self).toOpaque()
                AXObserverAddNotification(obs, window, kAXMovedNotification as CFString, selfPtr)
                AXObserverAddNotification(obs, window, kAXResizedNotification as CFString, selfPtr)

                // Also observe the app element itself for window-created events
                // (catches WhatsApp opening new panels / switching views)
                AXObserverAddNotification(obs, appElement, kAXWindowCreatedNotification as CFString, selfPtr)
                AXObserverAddNotification(obs, appElement, kAXFocusedWindowChangedNotification as CFString, selfPtr)
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    /// Stop observing a specific app.
    func stopObserving(pid: pid_t) {
        if let obs = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        callbacks.removeValue(forKey: pid)
    }

    /// Stop all observers.
    func stopAll() {
        for pid in observers.keys {
            stopObserving(pid: pid)
        }
    }

    // MARK: - Private Helpers

    /// Find the best window to observe, consistent with getWindowFrame logic.
    private func findTargetWindow(from windows: [AXUIElement]) -> AXUIElement? {
        // 1. Prefer AXMain
        for window in windows {
            var mainRef: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef)
            if let isMain = mainRef as? Bool, isMain {
                return window
            }
        }

        // 2. AXStandardWindow or AXDialog (Catalyst)
        for window in windows {
            var subroleRef: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
            if let subrole = subroleRef as? String,
               (subrole == "AXStandardWindow" || subrole == "AXDialog") {
                if let frame = frameForElement(window), frame.width >= 100, frame.height >= 100 {
                    return window
                }
            }
        }

        // 3. Largest window
        var bestWindow: AXUIElement? = nil
        var bestArea: CGFloat = 0
        for window in windows {
            guard let frame = frameForElement(window) else { continue }
            if frame.width < 100 || frame.height < 100 { continue }
            let area = frame.width * frame.height
            if area > bestArea {
                bestArea = area
                bestWindow = window
            }
        }

        // 4. Final fallback
        return bestWindow ?? windows.first
    }

    private func frameForElement(_ element: AXUIElement) -> CGRect? {
        var positionRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var position = CGPoint.zero
        var size = CGSize.zero

        guard let posVal = positionRef else { return nil }
        guard let sizeVal = sizeRef else { return nil }

        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    /// Called by AXObserver when a window notification fires.
    fileprivate func handleWindowChange(for element: AXUIElement) {
        // Find the PID for this element
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        guard let callback = callbacks[pid] else { return }

        // For window-created / focused-window-changed, re-query the main window
        // rather than using the element from the notification (which may be the app element)
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }),
           let frame = getWindowFrame(for: app) {
            callback(frame)
        } else if let frame = frameForElement(element) {
            callback(frame)
        }
    }
}

/// C callback for AXObserver — routes to WindowTracker instance.
private func windowChangeCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        tracker.handleWindowChange(for: element)
    }
}
