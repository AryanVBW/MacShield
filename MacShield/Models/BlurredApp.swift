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

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        name: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.isEnabled = isEnabled
    }

    /// Default chat apps that can be blurred.
    static let defaultApps: [BlurredApp] = [
        BlurredApp(bundleIdentifier: "com.hnc.Discord", name: "Discord"),
        BlurredApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack"),
        BlurredApp(bundleIdentifier: "net.whatsapp.WhatsApp", name: "WhatsApp"),
        BlurredApp(bundleIdentifier: "ru.keepcoder.Telegram", name: "Telegram"),
        BlurredApp(bundleIdentifier: "com.apple.MobileSMS", name: "Messages"),
        BlurredApp(bundleIdentifier: "com.facebook.archon", name: "Messenger"),
        BlurredApp(bundleIdentifier: "com.microsoft.teams2", name: "Teams"),
        BlurredApp(bundleIdentifier: "us.zoom.xos", name: "Zoom"),
        BlurredApp(bundleIdentifier: "com.skype.skype", name: "Skype"),
        BlurredApp(bundleIdentifier: "com.readdle.smartemail-macos", name: "Spark Mail"),
    ]
}
