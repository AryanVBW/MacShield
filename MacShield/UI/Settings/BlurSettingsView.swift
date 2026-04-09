import SwiftUI
import AppKit

/// Blur settings tab: chat blur toggle, intensity, reveal zone, per-app toggles, browser extensions.
///
/// Improvements:
/// - Live preview card below sliders shows exact blur appearance at current settings.
/// - Intensity shown as descriptive preset label (Light / Medium / Strong) alongside the number.
/// - Reveal mode shown as icon+label Picker instead of a plain toggle.
/// - New "Edge Softness" slider exposes featherWidth for fine-tuning.
/// - Blur-in animation toggle.
struct BlurSettingsView: View {
    @ObservedObject private var blurService = BlurOverlayService.shared

    /// Tracks hover position inside the live preview card.
    @State private var previewHover: CGPoint? = nil

    var body: some View {
        Form {
            // ── Global toggle ──────────────────────────────────────────────
            Section {
                Toggle("Enable Chat Blur", isOn: $blurService.isBlurActive)
                    .toggleStyle(.goldSwitch)
            }

            if blurService.isBlurActive {
                // ── Intensity controls ─────────────────────────────────────
                Section("Blur Settings") {
                    // Intensity slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Blur Intensity")
                                .font(MacShieldTypography.body)
                            Spacer()
                            intensityPresetLabel
                            Text("\(Int(blurService.blurIntensity))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(MacShieldColors.textSecondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                        Slider(value: $blurService.blurIntensity, in: 2...20, step: 1)
                            .tint(MacShieldColors.gold)
                    }

                    // Reveal size slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Reveal Zone Size")
                                .font(MacShieldTypography.body)
                            Spacer()
                            Text("\(Int(blurService.revealRadius)) pt")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(MacShieldColors.textSecondary)
                        }
                        Slider(value: $blurService.revealRadius, in: 100...400, step: 10)
                            .tint(MacShieldColors.gold)
                    }

                    // Edge softness slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Edge Softness")
                                .font(MacShieldTypography.body)
                            Spacer()
                            Text(featherLabel)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(MacShieldColors.textSecondary)
                        }
                        Slider(value: $blurService.featherWidth, in: 0.10...0.50, step: 0.02)
                            .tint(MacShieldColors.gold)
                        Text("Controls how gradually the reveal zone fades into the blur.")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                    }

                    // Reveal mode picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reveal Mode")
                            .font(MacShieldTypography.body)
                        Picker("", selection: $blurService.revealOnHover) {
                            Label("Hover to Reveal", systemImage: "cursorarrow.motionlines")
                                .tag(true)
                            Label("Click to Reveal", systemImage: "cursorarrow.click")
                                .tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Blur animate-in toggle
                    Toggle("Animate blur on/off (fade)", isOn: $blurService.blurAnimatesIn)
                        .toggleStyle(.goldSwitch)
                }

                // ── Live Preview ───────────────────────────────────────────
                Section("Live Preview") {
                    blurPreviewCard
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // ── Per-App toggles ────────────────────────────────────────
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

                // ── Keyboard shortcut info ─────────────────────────────────
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("Press")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                        shortcutBadge("⌥X")
                        Text("to toggle blur on/off")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // ── Browser Extensions ─────────────────────────────────────
                BrowserExtensionSettingsView()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Live Preview Card

    /// An inline preview of what the blur will look like at current settings.
    /// The user can hover over it to see the reveal zone in action.
    private var blurPreviewCard: some View {
        ZStack {
            // Simulated "chat content" behind the blur
            previewChatBubbles

            // Blur overlay using current settings
            BlurPreviewOverlay(
                intensity: blurService.blurIntensity,
                revealRadius: blurService.revealRadius,
                featherWidth: blurService.featherWidth,
                hoverPoint: previewHover
            )
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): previewHover = point
            case .ended:             previewHover = nil
            }
        }
        .overlay(
            Text("Hover to preview reveal")
                .font(MacShieldTypography.caption)
                .foregroundColor(.white.opacity(0.5))
                .padding(6),
            alignment: .bottomTrailing
        )
    }

    /// Fake chat bubbles displayed underneath the blur preview.
    private var previewChatBubbles: some View {
        ZStack {
            Color(hex: 0x1C1C1E)
            VStack(alignment: .leading, spacing: 8) {
                chatBubble("Hey! Did you see the update?", outgoing: false)
                chatBubble("Yes — shipping tomorrow 🎉", outgoing: true)
                chatBubble("Amazing! Here's the secret link:", outgoing: false)
                chatBubble("https://internal.example.com/rel…", outgoing: false)
            }
            .padding(14)
        }
    }

    private func chatBubble(_ text: String, outgoing: Bool) -> some View {
        HStack {
            if outgoing { Spacer() }
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(outgoing ? Color(hex: 0x0A84FF) : Color(hex: 0x3A3A3C))
                )
            if !outgoing { Spacer() }
        }
    }

    // MARK: - Helper Views

    private var intensityPresetLabel: some View {
        let label: String
        let color: Color
        switch blurService.blurIntensity {
        case 2..<7:
            label = "Light"; color = MacShieldColors.info
        case 7..<14:
            label = "Medium"; color = MacShieldColors.gold
        default:
            label = "Strong"; color = MacShieldColors.error
        }
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }

    private var featherLabel: String {
        switch blurService.featherWidth {
        case 0..<0.20: return "Sharp"
        case 0.20..<0.35: return "Medium"
        default: return "Soft"
        }
    }

    private func shortcutBadge(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(MacShieldColors.cardDark)
            )
    }
}

// MARK: - BlurPreviewOverlay

/// A lightweight preview-only blur overlay driven by an NSVisualEffectView mask.
/// Unlike BlurContentView (which drives a full window), this is embedded in a SwiftUI hierarchy.
private struct BlurPreviewOverlay: NSViewRepresentable {
    let intensity: Double
    let revealRadius: Double
    let featherWidth: Double
    let hoverPoint: CGPoint?

    func makeNSView(context: Context) -> BlurContentView {
        let view = BlurContentView(frame: .zero)
        view.revealOnHover = true
        updateView(view)
        return view
    }

    func updateNSView(_ nsView: BlurContentView, context: Context) {
        updateView(nsView)

        // Convert SwiftUI hover point (top-left origin) to AppKit (bottom-left)
        if let pt = hoverPoint {
            // In a NSViewRepresentable, the view's frame is already in AppKit coordinates.
            let height = nsView.bounds.height
            nsView.revealCenter = NSPoint(x: pt.x, y: height - pt.y)
        } else {
            nsView.revealCenter = nil
        }
    }

    private func updateView(_ view: BlurContentView) {
        view.blurRadius   = CGFloat(intensity)
        view.revealRadius = CGFloat(revealRadius * 0.38)   // scale down for the preview card
        view.featherWidth = CGFloat(featherWidth)
    }
}
