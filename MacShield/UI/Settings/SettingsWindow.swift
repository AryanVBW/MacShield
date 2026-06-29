import AppKit
import SwiftUI

/// Manages the Settings window lifecycle.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettings,
            object: nil
        )
    }

    @objc func openSettings(_ notification: Notification) {
        let targetScreen = notification.object as? NSScreen ?? NSScreen.main ?? NSScreen.screens[0]

        if let window {
            centerWindow(window, on: targetScreen)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacShield Settings"
        window.contentViewController = hostingController

        // macOS 15+/Tahoe regression: a SwiftUI NSHostingController set as the window's
        // contentViewController can be left at zero size and render as a blank/black
        // window unless its initial layout is resolved before the window is shown.
        // Forcing the constraint + layout pass here fixes the blank page.
        // See https://stackoverflow.com/a/79337455
        window.updateConstraintsIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()

        window.isReleasedWhenClosed = false
        centerWindow(window, on: targetScreen)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    private func centerWindow(_ window: NSWindow, on screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
