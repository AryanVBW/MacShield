import SwiftUI

/// Apps settings tab: manage the list of protected applications.
struct AppsSettingsView: View {
    @StateObject private var manager = ProtectedAppsManager.shared
    @State private var appPickerController = AppPickerWindowController()
    @State private var editingApp: ProtectedApp?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Protected Applications")
                .font(MacShieldTypography.title)

            if manager.apps.isEmpty {
                emptyState
            } else {
                appsList
            }

            Spacer()

            HStack {
                Spacer()
                PrimaryButton("Add App", icon: "plus") {
                    appPickerController.show(from: NSApp.keyWindow)
                }
            }
        }
        .padding()
        .sheet(item: $editingApp) { app in
            AppPasswordSheet(app: app, manager: manager) { editingApp = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.open")
                .font(.system(size: 40))
                .foregroundColor(MacShieldColors.textSecondary)
            Text("No protected apps yet")
                .font(MacShieldTypography.headline)
                .foregroundColor(.secondary)
            Text("Add apps to protect them with Touch ID or a password.")
                .font(MacShieldTypography.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var appsList: some View {
        List {
            ForEach(manager.apps) { app in
                // One Keychain attribute lookup per row render — apps are few.
                let hasCustomPassword = manager.hasCustomPassword(app)

                HStack(spacing: 12) {
                    AppIconView(bundleIdentifier: app.bundleIdentifier, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(MacShieldTypography.headline)
                        Text(app.allowBiometric
                             ? (hasCustomPassword ? "Touch ID + private password" : "Touch ID + backup password")
                             : "Private password only")
                            .font(MacShieldTypography.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    // Auto-close toggle
                    Button(action: { manager.toggleAutoClose(app) }) {
                        Image(systemName: app.autoClose ? "timer.circle.fill" : "timer")
                            .font(.system(size: 12))
                            .foregroundColor(app.autoClose ? MacShieldColors.gold : MacShieldColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(app.autoClose ? "Auto-close enabled" : "Enable auto-close when inactive")

                    // Per-app privacy password / Touch ID
                    Button(action: { editingApp = app }) {
                        Image(systemName: hasCustomPassword ? "key.fill" : "key")
                            .font(.system(size: 12))
                            .foregroundColor(hasCustomPassword ? MacShieldColors.gold : MacShieldColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(hasCustomPassword
                          ? "Private password set — click to change Touch ID or password"
                          : "Set a private password or disable Touch ID for this app")

                    Toggle("", isOn: Binding(
                        get: { app.isEnabled },
                        set: { _ in manager.toggleApp(app) }
                    ))
                    .toggleStyle(.goldSwitch)
                    .labelsHidden()

                    Button(action: { manager.removeApp(app) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(MacShieldColors.error)
                    }
                    .buttonStyle(.plain)
                }
                .id(app.id)
                .padding(.vertical, 4)
            }
            .onDelete { indexSet in
                let appsToRemove = indexSet.map { manager.apps[$0] }
                appsToRemove.forEach { manager.removeApp($0) }
            }
        }
    }
}

// MARK: - Per-App Password Sheet

/// Sheet for configuring a single app's privacy password and biometric preference.
private struct AppPasswordSheet: View {
    let app: ProtectedApp
    @ObservedObject var manager: ProtectedAppsManager
    let onClose: () -> Void

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var error: String?
    @State private var allowBiometric: Bool
    @State private var hasCustomPassword: Bool

    private let hasGlobalPassword = KeychainManager.shared.hasPassword()

    init(app: ProtectedApp, manager: ProtectedAppsManager, onClose: @escaping () -> Void) {
        self.app = app
        self.manager = manager
        self.onClose = onClose
        _allowBiometric = State(initialValue: app.allowBiometric)
        _hasCustomPassword = State(initialValue: manager.hasCustomPassword(app))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                AppIconView(bundleIdentifier: app.bundleIdentifier, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(MacShieldTypography.headline)
                    Text(hasCustomPassword ? "Private password set" : "No private password")
                        .font(MacShieldTypography.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Touch ID / Watch toggle
            Toggle("Allow Touch ID & Apple Watch", isOn: $allowBiometric)
                .toggleStyle(.goldSwitch)
                .onChange(of: allowBiometric) { newValue in
                    manager.setAllowBiometric(newValue, for: app)
                }

            Text(biometricExplanation)
                .font(MacShieldTypography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lockoutWarning {
                Label(lockoutWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(MacShieldTypography.caption)
                    .foregroundColor(MacShieldColors.locked)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Password fields
            Text(hasCustomPassword ? "Change Private Password" : "Set Private Password")
                .font(MacShieldTypography.body)

            SecureField("New password", text: $newPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)

            if let error {
                Text(error)
                    .font(MacShieldTypography.caption)
                    .foregroundColor(MacShieldColors.error)
            }

            // Actions
            HStack {
                if hasCustomPassword {
                    Button("Remove Password", role: .destructive) {
                        manager.removePassword(for: app)
                        hasCustomPassword = false
                        newPassword = ""
                        confirmPassword = ""
                        error = nil
                    }
                    .foregroundColor(MacShieldColors.error)
                }
                Spacer()
                Button("Done") { onClose() }
                PrimaryButton("Save Password") { savePassword() }
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Copy

    private var biometricExplanation: String {
        if allowBiometric {
            return "Unlock with Touch ID, Apple Watch, or the password below."
        }
        return "Touch ID and Apple Watch are disabled for this app. It can only be opened by typing its password."
    }

    /// Warn when disabling biometrics would leave the app with no usable password at all.
    private var lockoutWarning: String? {
        guard !allowBiometric, !hasCustomPassword, !hasGlobalPassword else { return nil }
        return "No password exists yet. Set a private password below (or a backup password in Security) — otherwise this app can only be managed from Settings."
    }

    // MARK: - Save

    private func savePassword() {
        guard !newPassword.isEmpty else {
            error = "Password cannot be empty."
            return
        }
        guard newPassword.count >= 4 else {
            error = "Password must be at least 4 characters."
            return
        }
        guard newPassword == confirmPassword else {
            error = "Passwords do not match."
            return
        }

        if manager.setPassword(newPassword, for: app) {
            hasCustomPassword = true
            newPassword = ""
            confirmPassword = ""
            error = nil
            onClose()
        } else {
            error = "Failed to save password. Please try again."
        }
    }
}
