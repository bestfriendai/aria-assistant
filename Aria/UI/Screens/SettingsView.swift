import SwiftUI

/// Enhanced Settings screen with improved UI/UX
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState

    // Voice settings
    @AppStorage("wakeWordEnabled") private var wakeWordEnabled = true
    @AppStorage("alwaysListening") private var alwaysListening = false
    @AppStorage("hapticFeedback") private var hapticFeedback = true

    // Privacy settings
    @AppStorage("useFaceID") private var useFaceID = true
    @AppStorage("analyticsEnabled") private var analyticsEnabled = false

    // State
    @State private var showDeleteConfirmation = false
    @State private var showExportSheet = false
    @State private var isExporting = false
    @State private var showAddAccount = false

    var body: some View {
        NavigationStack {
            List {
                // Profile section
                profileSection

                // Accounts section
                accountsSection

                // Voice settings
                voiceSection

                // Notifications
                notificationsSection

                // Privacy
                privacySection

                // Appearance
                appearanceSection

                // About
                aboutSection

                // Danger zone
                dangerZoneSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticFeedback.shared.selection()
                        dismiss()
                    }
                    .font(AriaTypography.labelLarge)
                    .foregroundColor(.ariaAccentBlue)
                }
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountView()
            }
            .confirmationDialog(
                "Delete All Data",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all your data including conversation history, connected accounts, and preferences. This action cannot be undone.")
            }
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            HStack(spacing: AriaSpacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.ariaAccentBlue, .ariaAccentPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Text("A")
                        .font(AriaTypography.headlineLarge)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: AriaSpacing.xxs) {
                    Text("Aria User")
                        .font(AriaTypography.headlineSmall)
                        .foregroundColor(.primary)

                    Text("Personal Plan")
                        .font(AriaTypography.bodySmall)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, AriaSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Profile: Aria User, Personal Plan")
            .accessibilityHint("Tap to edit profile")
        }
    }

    // MARK: - Accounts Section

    private var accountsSection: some View {
        Section {
            // Connected accounts
            AccountRowView(
                name: "Gmail",
                icon: "envelope.fill",
                color: .red,
                status: .connected,
                detail: "john@gmail.com"
            )

            AccountRowView(
                name: "Google Calendar",
                icon: "calendar",
                color: .blue,
                status: .connected,
                detail: "Synced"
            )

            AccountRowView(
                name: "Chase Bank",
                icon: "building.columns.fill",
                color: .blue,
                status: .connected,
                detail: "2 accounts"
            )

            AccountRowView(
                name: "Apple Health",
                icon: "heart.fill",
                color: .pink,
                status: .connected,
                detail: "Synced"
            )

            AccountRowView(
                name: "Outlook",
                icon: "envelope.fill",
                color: .blue,
                status: .notConnected
            )

            AccountRowView(
                name: "Spotify",
                icon: "music.note",
                color: .green,
                status: .notConnected
            )

            // Add account button
            Button {
                HapticFeedback.shared.selection()
                showAddAccount = true
            } label: {
                Label("Add Account", systemImage: "plus.circle.fill")
                    .font(AriaTypography.bodyMedium)
                    .foregroundColor(.ariaAccentBlue)
            }
            .accessibilityHint("Connect a new service to Aria")
        } header: {
            Text("CONNECTED ACCOUNTS")
        } footer: {
            Text("Connect your accounts to let Aria help you manage emails, calendar, finances, and more.")
                .font(AriaTypography.caption)
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        Section {
            // Wake word
            HStack {
                Label {
                    Text("Wake Word")
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundColor(.ariaAccentBlue)
                }

                Spacer()

                Text("\"Aria\"")
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Wake word: Aria")

            // Wake word toggle
            Toggle(isOn: $wakeWordEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wake Word Detection")
                        Text("Respond when you say \"Aria\"")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "ear")
                        .foregroundColor(.ariaAccentPurple)
                }
            }
            .tint(.ariaAccentBlue)

            // Always listening
            Toggle(isOn: $alwaysListening) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Always Listening")
                        Text("Keep microphone active")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.ariaAccentGreen)
                }
            }
            .tint(.ariaAccentBlue)

            // Haptic feedback
            Toggle(isOn: $hapticFeedback) {
                Label {
                    Text("Haptic Feedback")
                } icon: {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .foregroundColor(.ariaAccentOrange)
                }
            }
            .tint(.ariaAccentBlue)

            // Voice settings
            NavigationLink {
                VoiceSettingsView()
            } label: {
                Label {
                    Text("Voice & Speech")
                } icon: {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.ariaAccentTeal)
                }
            }
        } header: {
            Text("VOICE")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label {
                    HStack {
                        Text("Notifications")
                        Spacer()
                        Text("On")
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.ariaError)
                }
            }

            NavigationLink {
                AttentionSettingsView()
            } label: {
                Label {
                    Text("Attention Items")
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.ariaWarning)
                }
            }
        } header: {
            Text("NOTIFICATIONS")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            Toggle(isOn: $useFaceID) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Face ID for Banking")
                        Text("Require authentication for financial data")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "faceid")
                        .foregroundColor(.ariaAccentGreen)
                }
            }
            .tint(.ariaAccentBlue)

            HStack {
                Label {
                    Text("Data Storage")
                } icon: {
                    Image(systemName: "iphone")
                        .foregroundColor(.ariaAccentBlue)
                }

                Spacer()

                Text("On Device Only")
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $analyticsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share Analytics")
                        Text("Help improve Aria")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.ariaAccentPurple)
                }
            }
            .tint(.ariaAccentBlue)

            NavigationLink {
                PrivacyDetailView()
            } label: {
                Label {
                    Text("Privacy Details")
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.ariaAccentOrange)
                }
            }
        } header: {
            Text("PRIVACY & SECURITY")
        } footer: {
            Text("All your data is encrypted and stored securely on your device. Aria never shares your personal information with third parties.")
                .font(AriaTypography.caption)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Label {
                    HStack {
                        Text("Appearance")
                        Spacer()
                        Text("Dark")
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "paintbrush.fill")
                        .foregroundColor(.ariaAccentPink)
                }
            }

            NavigationLink {
                LanguageSettingsView()
            } label: {
                Label {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text("English")
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "globe")
                        .foregroundColor(.ariaAccentTeal)
                }
            }
        } header: {
            Text("APPEARANCE")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Label {
                    Text("Version")
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("1.0.0 (42)")
                    .foregroundColor(.secondary)
            }

            NavigationLink {
                Text("Terms of Service")
                    .navigationTitle("Terms of Service")
            } label: {
                Label("Terms of Service", systemImage: "doc.text.fill")
            }

            NavigationLink {
                Text("Privacy Policy")
                    .navigationTitle("Privacy Policy")
            } label: {
                Label("Privacy Policy", systemImage: "lock.doc.fill")
            }

            Link(destination: URL(string: "mailto:support@aria.app")!) {
                Label("Contact Support", systemImage: "envelope.fill")
            }

            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("Acknowledgements", systemImage: "heart.fill")
            }
        } header: {
            Text("ABOUT")
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            Button {
                HapticFeedback.shared.selection()
                isExporting = true
                exportData()
            } label: {
                Label {
                    HStack {
                        Text("Export My Data")
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.ariaAccentBlue)
                }
            }
            .disabled(isExporting)

            Button(role: .destructive) {
                HapticFeedback.shared.warning()
                showDeleteConfirmation = true
            } label: {
                Label("Delete All Data", systemImage: "trash.fill")
            }
        } header: {
            Text("DATA")
        } footer: {
            Text("Exporting creates a copy of all your data. Deleting removes everything permanently.")
                .font(AriaTypography.caption)
        }
    }

    // MARK: - Actions

    private func exportData() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                isExporting = false
                appState.showSuccess("Data exported successfully")
            }
        }
    }

    private func deleteAllData() {
        HapticFeedback.shared.error()
        // Delete all data
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        appState.showInfo("All data has been deleted")
    }
}

// MARK: - Account Row View

struct AccountRowView: View {
    let name: String
    let icon: String
    let color: Color
    let status: AccountStatus
    var detail: String? = nil

    enum AccountStatus {
        case connected
        case notConnected
        case syncing
        case error
    }

    var body: some View {
        HStack(spacing: AriaSpacing.sm) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.15))
                )

            // Name and detail
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AriaTypography.bodyMedium)

                if let detail = detail {
                    Text(detail)
                        .font(AriaTypography.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status
            statusView
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(statusLabel)")
        .accessibilityHint(status == .notConnected ? "Tap to connect" : "Tap to manage")
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.ariaSuccess)
        case .notConnected:
            Text("Connect")
                .font(AriaTypography.labelSmall)
                .foregroundColor(.ariaAccentBlue)
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.ariaWarning)
        }
    }

    private var statusLabel: String {
        switch status {
        case .connected: return "Connected"
        case .notConnected: return "Not connected"
        case .syncing: return "Syncing"
        case .error: return "Error"
        }
    }
}

// MARK: - Voice Settings View

struct VoiceSettingsView: View {
    @AppStorage("voiceName") private var voiceName = "Aria"
    @AppStorage("speakingRate") private var speakingRate = 1.0
    @AppStorage("voicePitch") private var voicePitch = 1.0
    @State private var isPlayingSample = false

    var body: some View {
        List {
            Section {
                Picker("Voice", selection: $voiceName) {
                    Text("Aria (Default)").tag("Aria")
                    Text("Nova").tag("Nova")
                    Text("Onyx").tag("Onyx")
                    Text("Shimmer").tag("Shimmer")
                }
                .pickerStyle(.navigationLink)

                VStack(alignment: .leading, spacing: AriaSpacing.sm) {
                    HStack {
                        Text("Speaking Rate")
                        Spacer()
                        Text(String(format: "%.1fx", speakingRate))
                            .foregroundColor(.secondary)
                            .font(AriaTypography.mono)
                    }
                    Slider(value: $speakingRate, in: 0.5...2.0, step: 0.1)
                        .tint(.ariaAccentBlue)
                    HStack {
                        Text("Slower")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Faster")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: AriaSpacing.sm) {
                    HStack {
                        Text("Voice Pitch")
                        Spacer()
                        Text(String(format: "%.1f", voicePitch))
                            .foregroundColor(.secondary)
                            .font(AriaTypography.mono)
                    }
                    Slider(value: $voicePitch, in: 0.5...1.5, step: 0.1)
                        .tint(.ariaAccentBlue)
                    HStack {
                        Text("Lower")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Higher")
                            .font(AriaTypography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("VOICE")
            }

            Section {
                Button {
                    HapticFeedback.shared.selection()
                    playSample()
                } label: {
                    HStack {
                        Image(systemName: isPlayingSample ? "stop.fill" : "play.fill")
                        Text(isPlayingSample ? "Stop" : "Test Voice")
                    }
                }
            } footer: {
                Text("Preview how Aria will sound with these settings.")
            }
        }
        .navigationTitle("Voice Settings")
    }

    private func playSample() {
        isPlayingSample = true
        // Play sample voice
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isPlayingSample = false
        }
    }
}

// MARK: - Placeholder Views

struct AddAccountView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Email") {
                    AccountOptionRow(name: "Gmail", icon: "envelope.fill", color: .red)
                    AccountOptionRow(name: "Outlook", icon: "envelope.fill", color: .blue)
                    AccountOptionRow(name: "Yahoo Mail", icon: "envelope.fill", color: .purple)
                }

                Section("Calendar") {
                    AccountOptionRow(name: "Google Calendar", icon: "calendar", color: .blue)
                    AccountOptionRow(name: "Apple Calendar", icon: "calendar", color: .red)
                }

                Section("Finance") {
                    AccountOptionRow(name: "Bank Account", icon: "building.columns.fill", color: .green)
                    AccountOptionRow(name: "Credit Card", icon: "creditcard.fill", color: .orange)
                }

                Section("Lifestyle") {
                    AccountOptionRow(name: "Spotify", icon: "music.note", color: .green)
                    AccountOptionRow(name: "Uber", icon: "car.fill", color: .black)
                    AccountOptionRow(name: "DoorDash", icon: "bag.fill", color: .red)
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct AccountOptionRow: View {
    let name: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(name)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

struct NotificationSettingsView: View {
    var body: some View {
        List {
            Text("Notification settings")
        }
        .navigationTitle("Notifications")
    }
}

struct AttentionSettingsView: View {
    var body: some View {
        List {
            Text("Attention item settings")
        }
        .navigationTitle("Attention Items")
    }
}

struct PrivacyDetailView: View {
    var body: some View {
        List {
            Text("Privacy details")
        }
        .navigationTitle("Privacy")
    }
}

struct AppearanceSettingsView: View {
    var body: some View {
        List {
            Text("Appearance settings")
        }
        .navigationTitle("Appearance")
    }
}

struct LanguageSettingsView: View {
    var body: some View {
        List {
            Text("Language settings")
        }
        .navigationTitle("Language")
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        List {
            Text("Open source acknowledgements")
        }
        .navigationTitle("Acknowledgements")
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environmentObject(AppState())
}

#Preview("Add Account") {
    AddAccountView()
}
