import SwiftUI

/// About window showing app version, credits, and links.
struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 16) {
            // App icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            // App name
            Text("MacShield")
                .font(MacShieldTypography.largeTitle)

            // Version
            Text("Version \(version) (\(build))")
                .font(MacShieldTypography.caption)
                .foregroundColor(.secondary)

            // Description
            Text("Lock any macOS app with Touch ID or password.")
                .font(MacShieldTypography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            // Credits
            VStack(spacing: 4) {
                Text("MacShield — Open Source Privacy")
                    .font(MacShieldTypography.body)
                Text("Free and open source under MIT License")
                    .font(MacShieldTypography.caption)
                    .foregroundColor(.secondary)
            }

            // GitHub link
            Link(destination: URL(string: "https://github.com/AryanVBW/MacShield")!) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                    Text("github.com/AryanVBW/MacShield")
                        .font(MacShieldTypography.caption)
                }
            }
        }
        .padding(32)
        .frame(width: 360, height: 380)
    }
}
