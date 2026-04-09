import SwiftUI

/// Password fallback input view shown in the lock overlay.
///
/// Improvements over baseline:
/// - Shake animation uses a single interpolating spring via `withAnimation` — no manual DispatchQueue chains.
/// - SecureField styled to MacShield's dark palette: tinted border, accent ring on focus.
/// - "Show Password" eye-toggle for standard usability.
struct PasswordInputView: View {
    @State private var password = ""
    @State private var showPassword = false
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var fieldFocused = false

    let onSuccess: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // Title
            Text("Enter Password")
                .font(MacShieldTypography.title)
                .foregroundColor(MacShieldColors.textPrimary)

            // Password field row
            HStack(spacing: 0) {
                passwordField
                    .textFieldStyle(.plain)
                    .frame(height: 36)
                    .padding(.horizontal, 12)
                    .onSubmit { verifyPassword() }

                // Eye toggle
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 13))
                        .foregroundColor(MacShieldColors.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .help(showPassword ? "Hide password" : "Show password")
            }
            .frame(width: 264)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        fieldFocused
                            ? MacShieldColors.gold
                            : Color.white.opacity(0.18),
                        lineWidth: fieldFocused ? 1.5 : 1.0
                    )
            )
            // Spring shake via offset — compatible with macOS 13+
            .offset(x: shakeOffset)

            // Error message
            if let errorMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(MacShieldColors.error)
                    Text(errorMessage)
                        .font(MacShieldTypography.caption)
                        .foregroundColor(MacShieldColors.error)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(MacShieldTypography.body)
                    .foregroundColor(MacShieldColors.textSecondary)

                PrimaryButton("Unlock") { verifyPassword() }
            }
        }
        .padding(36)
        .background(glassCard)
    }

    // MARK: - Password Field

    @ViewBuilder
    private var passwordField: some View {
        if showPassword {
            TextField("Password", text: $password)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(MacShieldColors.textPrimary)
        } else {
            SecureField("Password", text: $password)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(MacShieldColors.textPrimary)
        }
    }

    // MARK: - Glass Card

    private var glassCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.20), .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.50), radius: 32, x: 0, y: 12)
        .shadow(color: .black.opacity(0.20), radius: 6,  x: 0, y: 2)
    }

    // MARK: - Logic

    private func verifyPassword() {
        let result = AuthenticationService.shared.authenticateWithPassword(password)

        switch result {
        case .success:
            onSuccess()
        case .failure(let error):
            errorMessage = error.localizedDescription
            password = ""
            triggerShake()
        case .cancelled:
            break
        }
    }

    /// Smooth interpolating-spring shake — a single animation call, no DispatchQueue chains.
    private func triggerShake() {
        let spring = MacShieldAnimations.errorShakeSpring
        // Drive the offset through a spring: push right → spring settles back to 0.
        withAnimation(spring) {
            shakeOffset = 12
        }
        // After one cycle (~0.35s), kick back to rest.  The spring overshoot gives
        // the characteristic left-right wobble naturally.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            withAnimation(spring) {
                shakeOffset = 0
            }
        }
    }
}
