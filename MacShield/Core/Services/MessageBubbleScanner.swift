import AppKit
import ApplicationServices

// MARK: - Per-App Heuristics

/// Describes how to identify message row elements inside a specific app's AX tree.
private struct AppScanProfile {
    /// Accepted AX roles for a message row container (e.g. "AXGroup", "AXRow", "AXCell")
    let acceptedRoles: Set<String>
    /// Minimum height in points for an element to be considered a message row.
    let minHeight: CGFloat
    /// Minimum width fraction of the scroll area width (0–1).
    let minWidthFraction: CGFloat
    /// Maximum recursion depth to search for the message list container.
    let maxSearchDepth: Int
}

private let profiles: [String: AppScanProfile] = [
    // WhatsApp (Catalyst) — message rows are AXGroup inside an AXList
    "net.whatsapp.WhatsApp": AppScanProfile(
        acceptedRoles: ["AXGroup"],
        minHeight: 32, minWidthFraction: 0.4, maxSearchDepth: 10
    ),
    // iMessages
    "com.apple.MobileSMS": AppScanProfile(
        acceptedRoles: ["AXGroup"],
        minHeight: 28, minWidthFraction: 0.35, maxSearchDepth: 10
    ),
    // Telegram
    "ru.keepcoder.Telegram": AppScanProfile(
        acceptedRoles: ["AXGroup", "AXRow"],
        minHeight: 28, minWidthFraction: 0.35, maxSearchDepth: 10
    ),
    // Slack (Electron)
    "com.tinyspeck.slackmacgap": AppScanProfile(
        acceptedRoles: ["AXGroup"],
        minHeight: 28, minWidthFraction: 0.35, maxSearchDepth: 12
    ),
    // Discord (Electron)
    "com.hnc.Discord": AppScanProfile(
        acceptedRoles: ["AXGroup", "AXRow"],
        minHeight: 28, minWidthFraction: 0.35, maxSearchDepth: 12
    ),
    // Messenger
    "com.facebook.archon": AppScanProfile(
        acceptedRoles: ["AXGroup"],
        minHeight: 28, minWidthFraction: 0.35, maxSearchDepth: 10
    ),
    // Teams
    "com.microsoft.teams2": AppScanProfile(
        acceptedRoles: ["AXGroup", "AXRow"],
        minHeight: 28, minWidthFraction: 0.35, maxSearchDepth: 12
    ),
    // Skype
    "com.skype.skype": AppScanProfile(
        acceptedRoles: ["AXGroup"],
        minHeight: 28, minWidthFraction: 0.35, maxSearchDepth: 10
    ),
]

/// Fallback profile used when the bundle ID is not in `profiles`.
private let defaultProfile = AppScanProfile(
    acceptedRoles: ["AXGroup", "AXRow", "AXCell"],
    minHeight: 28, minWidthFraction: 0.30, maxSearchDepth: 10
)

// MARK: - MessageBubbleScanner

/// Walks the macOS Accessibility tree of a running app to find the screen-space
/// frames of visible message bubble rows.
///
/// Results are in **Accessibility coordinate space** (top-left origin),
/// matching the same coordinate space used by `WindowTracker` and `BlurWindowManager`.
/// Convert to AppKit coordinates using `BlurWindowManager.convertToAppKitCoordinates(_:)`.
///
/// The scanner is intentionally **stateless** — call `scan(pid:bundleID:)` whenever
/// you need fresh frames (e.g. on each timer tick or scroll event).
final class MessageBubbleScanner {
    static let shared = MessageBubbleScanner()
    private init() {}

    /// Maximum number of bubble frames returned (performance guard).
    private let maxBubbles = 60

    // MARK: - Public API

    /// Scan the running app identified by `pid` and return the screen frames of
    /// all visible message-row elements.
    ///
    /// Returns an empty array if:
    ///  - Accessibility permission is not granted.
    ///  - No message list is found within the AX tree.
    ///  - The app's window is not visible or minimized.
    func scan(pid: pid_t, bundleID: String) -> [CGRect] {
        let profile = profiles[bundleID] ?? defaultProfile
        let appElement = AXUIElementCreateApplication(pid)

        // Get all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              !windows.isEmpty else {
            return []
        }

        // Use the first (main) window
        let mainWindow = windows[0]

        // Get window frame to use for width-fraction filter
        let windowFrame = getFrame(of: mainWindow) ?? CGRect(x: 0, y: 0, width: 800, height: 600)

        // Find the scroll area that contains the message list
        var messageListElement: AXUIElement?
        findMessageList(in: mainWindow, profile: profile, depth: 0, result: &messageListElement)

        guard let listElement = messageListElement else {
            return []
        }

        return extractMessageFrames(
            from: listElement,
            profile: profile,
            windowWidth: windowFrame.width
        )
    }

    // MARK: - AX Tree Walk

    /// Recursively searches for a scroll area that contains a list/group of message rows.
    private func findMessageList(
        in element: AXUIElement,
        profile: AppScanProfile,
        depth: Int,
        result: inout AXUIElement?
    ) {
        guard depth < profile.maxSearchDepth, result == nil else { return }

        let role = getRole(of: element)

        // A scroll area whose first child looks like a message list
        if role == "AXScrollArea" {
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement],
               !children.isEmpty {
                // Check if children contain message-like elements
                let childRoles = children.prefix(5).compactMap { getRole(of: $0) }
                let hasListRole = childRoles.contains(where: { $0 == "AXList" || $0 == "AXTable" })
                let hasGroupRows = childRoles.contains(where: { profile.acceptedRoles.contains($0) })

                if hasListRole {
                    // Use the list/table child as the container
                    for child in children {
                        let r = getRole(of: child) ?? ""
                        if r == "AXList" || r == "AXTable" {
                            result = child
                            return
                        }
                    }
                } else if hasGroupRows {
                    // The scroll area itself directly contains the rows
                    result = element
                    return
                }
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            findMessageList(in: child, profile: profile, depth: depth + 1, result: &result)
            if result != nil { return }
        }
    }

    /// Extracts message frame rects from the children of the message list element.
    private func extractMessageFrames(
        from listElement: AXUIElement,
        profile: AppScanProfile,
        windowWidth: CGFloat
    ) -> [CGRect] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(listElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return []
        }

        let minWidth = windowWidth * profile.minWidthFraction
        var frames: [CGRect] = []

        for child in children {
            guard let role = getRole(of: child),
                  profile.acceptedRoles.contains(role),
                  let frame = getFrame(of: child),
                  frame.height >= profile.minHeight,
                  frame.width >= minWidth else { continue }

            frames.append(frame)

            if frames.count >= maxBubbles { break }
        }

        return frames
    }

    // MARK: - AX Helpers

    private func getRole(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }

    /// Returns the element's frame in Accessibility coordinates (top-left origin, screen space).
    func getFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }
}
