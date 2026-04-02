import SwiftUI
import SafariServices

/// Settings section for browser extension controls.
struct BrowserExtensionSettingsView: View {
    var body: some View {
        Section("Browser Extensions") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "safari")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safari Extension")
                            .font(MacShieldTypography.headline)
                        Text("Enable in Safari → Settings → Extensions")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open Safari Settings") {
                        SFSafariApplication.showPreferencesForExtension(
                            withIdentifier: "com.macshield.web-extension"
                        ) { error in
                            if let error {
                                NSLog("[MacShield] Safari extension settings error: %@", error.localizedDescription)
                            }
                        }
                    }
                    .font(MacShieldTypography.caption)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chrome / Edge / Brave")
                            .font(MacShieldTypography.headline)
                        Text("Load from BrowserExtensions/Chrome folder")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Show in Finder") {
                        if let bundlePath = Bundle.main.resourcePath {
                            let extensionPath = (bundlePath as NSString)
                                .deletingLastPathComponent + "/BrowserExtensions/Chrome"
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: extensionPath)
                        }
                    }
                    .font(MacShieldTypography.caption)
                }
            }

            Text("Browser blur works on: WhatsApp Web, Instagram, Telegram, Discord, Slack, X/Twitter, LinkedIn, Gmail, Teams, Messenger, Google Messages")
                .font(MacShieldTypography.caption)
                .foregroundColor(.secondary)
        }
    }
}
