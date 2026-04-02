import ApplicationServices
import AppKit

/// Tracks target app windows via the Accessibility API.
/// Provides window frame queries and move/resize observation.
final class WindowTracker {
    static let shared = WindowTracker()

    private var observers: [pid_t: AXObserver] = [:]
    private var callbacks: [pid_t: (CGRect) -> Void] = [:]

    private init() {}

    // MARK: - Window Frame

    /// Get the frame of the frontmost window for the given app.
    func getWindowFrame(for app: NSRunningApplication) -> CGRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first else { return nil }

        return frameForElement(window)
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

        if let windows = windowsRef as? [AXUIElement], let window = windows.first {
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(obs, window, kAXMovedNotification as CFString, selfPtr)
            AXObserverAddNotification(obs, window, kAXResizedNotification as CFString, selfPtr)
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

    // MARK: - Private

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

        guard let callback = callbacks[pid],
              let frame = frameForElement(element) else { return }
        callback(frame)
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
