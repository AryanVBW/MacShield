import Foundation

// MARK: - Blur Mode

/// Controls whether MacShield blurs the whole chat content area or only individual message bubbles.
enum BlurMode: String, Codable, Hashable, CaseIterable {
    /// Blur the entire chat pane (original behaviour).
    case fullChatArea
    /// Walk the Accessibility tree and blur only individual message-row elements.
    /// Falls back to `fullChatArea` if no elements are found.
    case perMessageBubble

    var displayName: String {
        switch self {
        case .fullChatArea:   return "Full Chat Area"
        case .perMessageBubble: return "Message Bubbles Only"
        }
    }
}

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

    /// Whether to blur the full chat pane or only per-message-bubble elements (via AX scan).
    var blurMode: BlurMode

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        name: String,
        isEnabled: Bool = true,
        contentInsets: ContentInsets = .none,
        blurMode: BlurMode = .perMessageBubble
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.isEnabled = isEnabled
        self.contentInsets = contentInsets
        self.blurMode = blurMode
    }

    /// Default chat apps that can be blurred, with per-app content insets.
    ///
    /// Insets are tuned so only the chat/content area is blurred.
    /// The sidebar, server list, toolbar, and title bar stay unblurred.
    static let defaultApps: [BlurredApp] = [
        // Discord — bubble mode; fallback insets guard sidebar area
        BlurredApp(bundleIdentifier: "com.hnc.Discord", name: "Discord",
                   contentInsets: ContentInsets(top: 48, left: 72, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // Slack — bubble mode
        BlurredApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack",
                   contentInsets: ContentInsets(top: 38, left: 260, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // WhatsApp — bubble mode
        BlurredApp(bundleIdentifier: "net.whatsapp.WhatsApp", name: "WhatsApp",
                   contentInsets: ContentInsets(top: 56, left: 320, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // Telegram — bubble mode
        BlurredApp(bundleIdentifier: "ru.keepcoder.Telegram", name: "Telegram",
                   contentInsets: ContentInsets(top: 56, left: 310, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // Messages — bubble mode
        BlurredApp(bundleIdentifier: "com.apple.MobileSMS", name: "Messages",
                   contentInsets: ContentInsets(top: 52, left: 280, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // Messenger — bubble mode
        BlurredApp(bundleIdentifier: "com.facebook.archon", name: "Messenger",
                   contentInsets: ContentInsets(top: 56, left: 280, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // Teams — bubble mode
        BlurredApp(bundleIdentifier: "com.microsoft.teams2", name: "Teams",
                   contentInsets: ContentInsets(top: 48, left: 260, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // Zoom — full area blur (chat is mixed with video UI)
        BlurredApp(bundleIdentifier: "us.zoom.xos", name: "Zoom",
                   contentInsets: .none,
                   blurMode: .fullChatArea),

        // Skype — bubble mode
        BlurredApp(bundleIdentifier: "com.skype.skype", name: "Skype",
                   contentInsets: ContentInsets(top: 52, left: 260, bottom: 0, right: 0),
                   blurMode: .perMessageBubble),

        // Spark Mail — full area blur (email layout)
        BlurredApp(bundleIdentifier: "com.readdle.smartemail-macos", name: "Spark Mail",
                   contentInsets: ContentInsets(top: 44, left: 240, bottom: 0, right: 0),
                   blurMode: .fullChatArea),
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
