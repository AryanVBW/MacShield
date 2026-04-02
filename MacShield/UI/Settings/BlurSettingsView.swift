import SwiftUI

/// Blur settings tab: chat blur toggle, intensity, reveal zone, per-app toggles, browser extensions.
struct BlurSettingsView: View {
    @ObservedObject private var blurService = BlurOverlayService.shared

    var body: some View {
        Form {
            // SECTION: Global blur toggle
            Section {
                Toggle("Enable Chat Blur", isOn: $blurService.isBlurActive)
                    .toggleStyle(.goldSwitch)

                if blurService.isBlurActive {
                    // Blur intensity slider
                    HStack {
                        Text("Blur Intensity:")
                        Slider(value: $blurService.blurIntensity, in: 2...20, step: 1)
                        Text("\(Int(blurService.blurIntensity))px")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }

                    // Reveal zone size slider
                    HStack {
                        Text("Reveal Size:")
                        Slider(value: $blurService.revealRadius, in: 100...400, step: 10)
                        Text("\(Int(blurService.revealRadius))pt")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }

                    // Reveal mode
                    Toggle("Reveal on hover (off = click to reveal)", isOn: $blurService.revealOnHover)
                        .toggleStyle(.goldSwitch)
                }
            }

            if blurService.isBlurActive {
                // SECTION: Per-app blur toggles
                Section("Blurred Apps") {
                    ForEach(blurService.blurredApps) { app in
                        HStack(spacing: 12) {
                            AppIconView(bundleIdentifier: app.bundleIdentifier, size: 24)
                            Text(app.name)
                                .font(MacShieldTypography.body)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { app.isEnabled },
                                set: { _ in blurService.toggleApp(app) }
                            ))
                            .toggleStyle(.goldSwitchSmall)
                            .labelsHidden()
                        }
                    }

                    Text("Chat content in these apps will be blurred. Hover over messages to reveal them.")
                        .font(MacShieldTypography.caption)
                        .foregroundColor(.secondary)
                }

                // SECTION: Keyboard shortcut info
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("Press")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                        Text("⌥X")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(MacShieldColors.cardDark)
                            )
                        Text("to toggle blur on/off")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // SECTION: Browser extensions
                BrowserExtensionSettingsView()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
