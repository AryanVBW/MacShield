import AppKit
import SwiftUI

/// Manages the NSStatusItem and menu bar icon states.
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// Current lock state displayed in the menu bar.
    enum IconState {
        /// No protected apps are running.
        case idle
        /// A protected app is running (unlocked).
        case active
        /// An overlay is currently displayed.
        case locked
    }

    var iconState: IconState = .idle {
        didSet { updateIcon() }
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set initial icon based on protection state
        iconState = Defaults.shared.appSettings.isProtectionEnabled ? .active : .idle

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 260, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView(
            onToggleProtection: { [weak self] in
                self?.toggleProtection()
            },
            onSettingsClicked: { [weak self] in
                self?.hidePopover()
                let screen = self?.statusItem?.button?.window?.screen
                NotificationCenter.default.post(name: .openSettings, object: screen)
            },
            onQuitClicked: {
                NSApplication.shared.terminate(nil)
            }
        ))
        self.popover = popover

        if let button = statusItem?.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            hidePopover()
        } else {
            // Require authentication before showing the popover
            SettingsAuthService.shared.authenticate { [weak self] success in
                guard success else { return }
                NSApp.activate(ignoringOtherApps: true)
                self?.popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func hidePopover() {
        popover?.performClose(nil)
    }

    private func toggleProtection() {
        var settings = Defaults.shared.appSettings
        settings.isProtectionEnabled.toggle()
        Defaults.shared.appSettings = settings

        if !settings.isProtectionEnabled {
            OverlayWindowService.shared.dismissAll()
            iconState = .idle
        } else {
            iconState = .active
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        // Load the custom SVG icon from the app bundle.
        // Falls back to SF Symbol "shield" if the file is missing.
        let customIcon: NSImage? = {
            guard let url = Bundle.main.url(forResource: "macshield_icon", withExtension: "svg"),
                  let img = NSImage(contentsOf: url) else {
                NSLog("[MacShield] macshield_icon.svg not found in bundle – falling back to SF Symbol")
                return nil
            }
            return img
        }()

        let menuBarSize = NSSize(width: 18, height: 18)

        if let source = customIcon {
            // Build a correctly-sized composited image for the current state.
            let rendered = NSImage(size: menuBarSize, flipped: false) { rect in
                // For idle state: draw at reduced opacity to signal protection is off.
                let alpha: CGFloat = self.iconState == .idle ? 0.45 : 1.0
                source.draw(in: rect,
                            from: NSRect(origin: .zero, size: source.size),
                            operation: .sourceOver,
                            fraction: alpha)

                // Locked state: draw a small orange badge dot in the top-right corner.
                if self.iconState == .locked {
                    NSColor.systemOrange.setFill()
                    let dot = NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)
                    NSBezierPath(ovalIn: dot).fill()
                }
                return true
            }
            rendered.isTemplate = false   // keep full colour
            button.image = rendered
        } else {
            // ── Fallback: SF Symbols (original behaviour) ──────────────────
            let symbolName: String
            switch iconState {
            case .idle:   symbolName = "shield.slash"
            case .active: symbolName = "shield"
            case .locked: symbolName = "shield.fill"
            }
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MacShield")

            if iconState == .locked, let baseImage = image {
                let badged = NSImage(size: menuBarSize, flipped: false) { rect in
                    baseImage.draw(in: NSRect(x: 0, y: 2, width: 14, height: 14))
                    NSColor.systemOrange.setFill()
                    NSBezierPath(ovalIn: NSRect(x: 12, y: 12, width: 6, height: 6)).fill()
                    return true
                }
                badged.isTemplate = false
                button.image = badged
            } else {
                button.image = image
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openSettings = Notification.Name("com.macshield.app.openSettings")
}
