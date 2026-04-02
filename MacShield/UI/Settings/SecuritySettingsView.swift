import SwiftUI

/// Security settings tab: authentication method, backup password.
struct SecuritySettingsView: View {
    @State private var settings = Defaults.shared.appSettings
    @State private var hasBackupPassword = false
    @State private var showPasswordSheet = false
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Require authentication on app launch", isOn: $settings.requireAuthOnLaunch)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: settings.requireAuthOnLaunch) { _ in
                        Defaults.shared.appSettings = settings
                    }

                Toggle("Require authentication on app switch", isOn: $settings.requireAuthOnActivate)
                    .toggleStyle(.goldSwitch)
                    .onChange(of: settings.requireAuthOnActivate) { _ in
                        Defaults.shared.appSettings = settings
                    }
            }

            Section("Touch ID") {
                HStack {
                    Image(systemName: "touchid")
                        .font(.system(size: 20))
                        .foregroundColor(AuthenticationService.shared.isTouchIDAvailable ? MacShieldColors.success : MacShieldColors.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AuthenticationService.shared.isTouchIDAvailable ? "Touch ID Available" : "Touch ID Not Available")
                            .font(MacShieldTypography.body)
                        if !AuthenticationService.shared.isTouchIDAvailable {
                            Text("Touch ID is not configured on this Mac. Use a backup password instead.")
                                .font(MacShieldTypography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Backup Password") {
                if hasBackupPassword {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(MacShieldColors.success)
                        Text("Backup password is set")
                            .font(MacShieldTypography.body)
                    }

                    Button("Change Password...") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(MacShieldColors.locked)
                        Text("No backup password set")
                            .font(MacShieldTypography.body)
                    }

                    Text("A backup password lets you unlock apps when Touch ID is unavailable.")
                        .font(MacShieldTypography.caption)
                        .foregroundColor(.secondary)

                    Button("Set Password...") {
                        resetPasswordFields()
                        showPasswordSheet = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            hasBackupPassword = KeychainManager.shared.hasPassword()
        }
        .sheet(isPresented: $showPasswordSheet) {
            passwordSheet
        }
    }

    // MARK: - Password Sheet

    private var passwordSheet: some View {
        VStack(spacing: 16) {
            Text(hasBackupPassword ? "Change Password" : "Set Backup Password")
                .font(MacShieldTypography.title)

            SecureField("New Password", text: $newPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            if let passwordError {
                Text(passwordError)
                    .font(MacShieldTypography.caption)
                    .foregroundColor(MacShieldColors.error)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showPasswordSheet = false
                }

                PrimaryButton("Save") {
                    savePassword()
                }
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func savePassword() {
        guard !newPassword.isEmpty else {
            passwordError = "Password cannot be empty."
            return
        }

        guard newPassword.count >= 4 else {
            passwordError = "Password must be at least 4 characters."
            return
        }

        guard newPassword == confirmPassword else {
            passwordError = "Passwords do not match."
            return
        }

        let saved = KeychainManager.shared.savePassword(newPassword)
        if saved {
            Defaults.shared.isBackupPasswordSet = true
            hasBackupPassword = true
            showPasswordSheet = false
        } else {
            passwordError = "Failed to save password. Please try again."
        }
    }

    private func resetPasswordFields() {
        newPassword = ""
        confirmPassword = ""
        passwordError = nil
    }
}
