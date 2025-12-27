import SwiftUI

/// Settings screen
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("wakeWordEnabled") private var wakeWordEnabled = true
    @AppStorage("alwaysListening") private var alwaysListening = false
    @AppStorage("hapticFeedback") private var hapticFeedback = true

    var body: some View {
        NavigationStack {
            List {
                // Accounts
                Section {
                    AccountRow(
                        name: "Gmail",
                        icon: "envelope.fill",
                        color: .red,
                        isConnected: true
                    )
                    AccountRow(
                        name: "Outlook",
                        icon: "envelope.fill",
                        color: .blue,
                        isConnected: false
                    )
                    AccountRow(
                        name: "Chase Bank",
                        icon: "building.columns.fill",
                        color: .blue,
                        isConnected: true
                    )
                    AccountRow(
                        name: "Instacart",
                        icon: "cart.fill",
                        color: .green,
                        isConnected: false
                    )

                    Button {
                        // Add account
                    } label: {
                        Label("Add Account", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("ACCOUNTS")
                }

                // Voice
                Section {
                    HStack {
                        Text("Wake Word")
                        Spacer()
                        Text("\"Aria\"")
                            .foregroundColor(.secondary)
                    }

                    Toggle("Wake Word Detection", isOn: $wakeWordEnabled)

                    Toggle("Always Listening", isOn: $alwaysListening)

                    Toggle("Haptic Feedback", isOn: $hapticFeedback)

                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        Text("Voice Settings")
                    }
                } header: {
                    Text("VOICE")
                }

                // Privacy
                Section {
                    HStack {
                        Text("Face ID for Banking")
                        Spacer()
                        Image(systemName: "faceid")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Data Storage")
                        Spacer()
                        Text("On Device Only")
                            .foregroundColor(.secondary)
                    }

                    Button {
                        // Export data
                    } label: {
                        Text("Export My Data")
                    }

                    Button(role: .destructive) {
                        // Delete data
                    } label: {
                        Text("Delete All Data")
                    }
                } header: {
                    Text("PRIVACY")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        Text("Terms of Service")
                    } label: {
                        Text("Terms of Service")
                    }

                    NavigationLink {
                        Text("Privacy Policy")
                    } label: {
                        Text("Privacy Policy")
                    }

                    Link(destination: URL(string: "mailto:support@aria.app")!) {
                        Text("Contact Support")
                    }
                } header: {
                    Text("ABOUT")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Account row in settings
struct AccountRow: View {
    let name: String
    let icon: String
    let color: Color
    let isConnected: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(name)

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Text("Connect")
                    .foregroundColor(.blue)
            }
        }
    }
}

/// Voice settings detail view
struct VoiceSettingsView: View {
    @AppStorage("voiceName") private var voiceName = "Aria"
    @AppStorage("speakingRate") private var speakingRate = 1.0

    var body: some View {
        List {
            Section {
                Picker("Voice", selection: $voiceName) {
                    Text("Aria").tag("Aria")
                    Text("Nova").tag("Nova")
                    Text("Onyx").tag("Onyx")
                }

                VStack(alignment: .leading) {
                    Text("Speaking Rate")
                    Slider(value: $speakingRate, in: 0.5...2.0, step: 0.1)
                    HStack {
                        Text("Slow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Fast")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button("Test Voice") {
                    // Play sample
                }
            }
        }
        .navigationTitle("Voice Settings")
    }
}

#Preview {
    SettingsView()
}
