import Foundation

/// An application that the user has chosen to blur with MacShield's Chat Blur.
struct BlurredApp: Codable, Identifiable, Hashable {
    /// Unique identifier for this entry.
    let id: UUID

    /// The app's bundle identifier (e.g. "com.hnc.Discord").
    let bundleIdentifier: String

    /// Display name (e.g. "Discord").
    let name: String

    /// Whether blur is currently enabled for this app.
    var isEnabled: Bool

    /// Insets from the window edges to the content area that should be blurred.
    /// Areas outside these insets (sidebar, toolbar, window chrome) stay clear.
    /// Values in points; 0 = blur starts at the window edge.
    var contentInsets: ContentInsets

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        name: String,
        isEnabled: Bool = true,
        contentInsets: ContentInsets = .none
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.isEnabled = isEnabled
        self.contentInsets = contentInsets
    }

    /// Default chat apps that can be blurred, with per-app content insets.
    ///
    /// Insets are tuned so only the chat/content area is blurred.
    /// The sidebar, server list, toolbar, and title bar stay unblurred.
    static let defaultApps: [BlurredApp] = [
        // Discord: 72px server icon rail + 240px channels sidebar = 312 left; 48px top toolbar
        BlurredApp(bundleIdentifier: "com.hnc.Discord", name: "Discord",
                   contentInsets: ContentInsets(top: 48, left: 72, bottom: 0, right: 0)),

        // Slack: ~260px sidebar; ~38px top toolbar
        BlurredApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack",
                   contentInsets: ContentInsets(top: 38, left: 260, bottom: 0, right: 0)),

        // WhatsApp: ~320px sidebar; ~56px top toolbar
        BlurredApp(bundleIdentifier: "net.whatsapp.WhatsApp", name: "WhatsApp",
                   contentInsets: ContentInsets(top: 56, left: 320, bottom: 0, right: 0)),

        // Telegram: ~310px sidebar; ~56px top toolbar
        BlurredApp(bundleIdentifier: "ru.keepcoder.Telegram", name: "Telegram",
                   contentInsets: ContentInsets(top: 56, left: 310, bottom: 0, right: 0)),

        // Messages: ~280px sidebar; ~52px top toolbar
        BlurredApp(bundleIdentifier: "com.apple.MobileSMS", name: "Messages",
                   contentInsets: ContentInsets(top: 52, left: 280, bottom: 0, right: 0)),

        // Messenger: ~280px sidebar; ~56px top toolbar
        BlurredApp(bundleIdentifier: "com.facebook.archon", name: "Messenger",
                   contentInsets: ContentInsets(top: 56, left: 280, bottom: 0, right: 0)),

        // Teams: ~260px sidebar; ~48px top toolbar
        BlurredApp(bundleIdentifier: "com.microsoft.teams2", name: "Teams",
                   contentInsets: ContentInsets(top: 48, left: 260, bottom: 0, right: 0)),

        // Zoom: full blur (chat is mixed with video UI)
        BlurredApp(bundleIdentifier: "us.zoom.xos", name: "Zoom",
                   contentInsets: .none),

        // Skype: ~260px sidebar; ~52px top toolbar
        BlurredApp(bundleIdentifier: "com.skype.skype", name: "Skype",
                   contentInsets: ContentInsets(top: 52, left: 260, bottom: 0, right: 0)),

        // Spark Mail: ~240px sidebar; ~44px top toolbar
        BlurredApp(bundleIdentifier: "com.readdle.smartemail-macos", name: "Spark Mail",
                   contentInsets: ContentInsets(top: 44, left: 240, bottom: 0, right: 0)),
    ]
}

// MARK: - Content Insets

extension BlurredApp {
    /// Insets from window edges to the content area that should be blurred.
    ///
    /// Example: WhatsApp has a ~320px sidebar on the left and a ~56px toolbar on top.
    /// Setting `left: 320, top: 56` means the blur only covers the chat message area,
    /// leaving the sidebar and toolbar fully visible.
    struct ContentInsets: Codable, Hashable {
        var top: CGFloat
        var left: CGFloat
        var bottom: CGFloat
        var right: CGFloat

        init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }

        /// No insets — blur covers the full window.
        static let none = ContentInsets()

        /// Whether any inset is non-zero.
        var hasInsets: Bool {
            top > 0 || left > 0 || bottom > 0 || right > 0
        }
    }
}
