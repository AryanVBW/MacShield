import SwiftUI
import AppKit

/// The lock overlay UI: blur background with centered unlock card.
///
/// Visual improvements:
/// - Material: .fullScreenUI (strongest blur) + Reduce Transparency adaptive tint
/// - Card: glassmorphism via ultraThinMaterial + white stroke border + multi-layer shadow
/// - Entrance: cinematic scale(0.96 → 1.0) + opacity fade, springs tuned to macOS HIG
/// - Lock icon: subtle breathing pulse animation while Touch ID is pending
/// - Reduce Motion: all animations disabled when system preference is active
/// - Touch ID triggers automatically on appear — no user interaction needed for the happy path.
struct LockOverlayView: View {
    let appName: String
    let bundleIdentifier: String
    let isPrimary: Bool
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var showPasswordInput = false
    @State private var authState: AuthState = .authenticating
    @State private var errorMessage: String?
    @State private var lockPulse: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum AuthState {
        case authenticating
        case waitingForUser
    }

    // MARK: - Adaptive tint

    /// Opacity for the black tint overlay.
    /// When "Reduce Transparency" is on we go near-opaque so no content bleeds through.
    private var adaptiveTintOpacity: Double {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0.80 : 0.42
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Background ────────────────────────────────────────────────
            // Strongest available material: .fullScreenUI blurs the entire display
            // content behind this panel, with .darkAqua forced for maximum contrast.
            BlurView(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()
                .overlay(
                    // Adaptive dark tint: near-solid when Reduce Transparency is on
                    Color.black.opacity(adaptiveTintOpacity)
                        .ignoresSafeArea()
                )

            // ── Foreground content ────────────────────────────────────────
            if showPasswordInput {
                PasswordInputView(
                    onSuccess: { onDismiss() },
                    onCancel: {
                        showPasswordInput = false
                    }
                )
                .transition(.opacity)
            } else {
                unlockCard
                    .scaleEffect(isVisible ? 1.0 : 0.96)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .transition(.opacity)
            }
        }
        .onAppear {
            let appear = reduceMotion
                ? MacShieldAnimations.adapted(MacShieldAnimations.overlayAppear)
                : MacShieldAnimations.overlayAppear
            withAnimation(appear) {
                isVisible = true
            }
            if isPrimary {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    attemptTouchID()
                }
            }
            // Start lock icon breathing pulse
            if !reduceMotion {
                startLockPulse()
            }
        }
    }

    // MARK: - Unlock Card

    private var unlockCard: some View {
        VStack(spacing: 22) {
            // App icon
            AppIconView(bundleIdentifier: bundleIdentifier, size: 68)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

            // Lock pulse icon
            Image(systemName: authState == .authenticating ? "touchid" : "lock.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(authState == .authenticating ? MacShieldColors.gold : MacShieldColors.locked)
                .scaleEffect(lockPulse && !reduceMotion ? 1.08 : 1.0)
                .opacity(lockPulse && !reduceMotion ? 0.75 : 1.0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                    value: lockPulse
                )

            // Title
            Text("\(appName) is Locked")
                .font(MacShieldTypography.largeTitle)
                .foregroundColor(MacShieldColors.textPrimary)

            // Auth state content
            Group {
                if authState == .authenticating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(MacShieldColors.textSecondary)
                        Text("Authenticating…")
                            .font(MacShieldTypography.body)
                            .foregroundColor(MacShieldColors.textSecondary)
                    }
                    .padding(.top, 2)
                } else {
                    VStack(spacing: 12) {
                        if let errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(MacShieldColors.error)
                                Text(errorMessage)
                                    .font(MacShieldTypography.caption)
                                    .foregroundColor(MacShieldColors.error)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        PrimaryButton("Try Again", icon: "touchid") {
                            attemptTouchID()
                        }

                        SecondaryButton("Use Password Instead") {
                            OverlayWindowService.shared.enableKeyboardInput()
                            withAnimation(MacShieldAnimations.adapted(MacShieldAnimations.standard)) {
                                showPasswordInput = true
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }

            #if DEBUG
            Button("Skip (Dev)") { onDismiss() }
                .font(MacShieldTypography.caption)
                .foregroundColor(MacShieldColors.error)
                .padding(.top, 6)
            #endif
        }
        .padding(44)
        .background(glassCard)
    }

    // MARK: - Glass Card

    /// Glassmorphic card: ultraThinMaterial fill + subtle white stroke + layered shadows.
    private var glassCard: some View {
        ZStack {
            // Base: ultra-thin system material (adapts to dark/light automatically)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)

            // Stroke: very subtle white border that catches ambient light
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)

            // Inner edge highlight (top-left bright rim, bottom-right dim)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        // Layered shadow: large soft + smaller crisp
        .shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 16)
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
    }

    // MARK: - Touch ID

    private func attemptTouchID() {
        authState = .authenticating
        errorMessage = nil
        if !reduceMotion { startLockPulse() }

        OverlayWindowService.shared.setTouchIDMode(true)

        AuthenticationService.shared.authenticateWithTouchID(
            reason: "Unlock \(appName)"
        ) { result in
            OverlayWindowService.shared.setTouchIDMode(false)
            switch result {
            case .success:
                onDismiss()
            case .failure(let error):
                authState = .waitingForUser
                errorMessage = error.localizedDescription
                lockPulse = false
            case .cancelled:
                authState = .waitingForUser
                lockPulse = false
            }
        }
    }

    private func startLockPulse() {
        lockPulse = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            lockPulse = true
        }
    }
}


