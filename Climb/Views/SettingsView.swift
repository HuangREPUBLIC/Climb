import SwiftUI
import SwiftData

/// The Matches tab's gear: account, API keys and log out; syncing and switching live in LinkAccountView.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [LinkedAccount]
    @State private var showingLinkAccount = false
    @State private var confirmingLogOut = false
    @State private var isLoggingOut = false

    private var account: LinkedAccount? { accounts.first }

    var body: some View {
        Form {
            if let account {
                Section("Riot Account") {
                    HStack(spacing: 12) {
                        if let iconID = account.profileIconID {
                            ProfileIconView(profileIconID: iconID, size: 44)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.riotID)
                                .font(.headline)
                            Text(RiotPlatform(rawValue: account.platform)?.displayName ?? account.platform)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    Button("Sync or Switch Account", systemImage: "arrow.triangle.2.circlepath") {
                        showingLinkAccount = true
                    }
                }
            }

            Section {
                NavigationLink {
                    APIKeysView()
                } label: {
                    Label("API Keys", systemImage: "key")
                }
            } footer: {
                Text("Riot personal keys expire every 24 hours.")
            }

            Section {
                Button(role: .destructive) {
                    confirmingLogOut = true
                } label: {
                    Label(isLoggingOut ? "Logging Out…" : "Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                // On the button so the popover points at this row; on the Form it covered the account rows.
                .confirmationDialog(
                    "Log out of \(account?.riotID ?? "Climb")?",
                    isPresented: $confirmingLogOut,
                    titleVisibility: .visible
                ) {
                    Button("Log Out", role: .destructive, action: logOut)
                } message: {
                    Text("Saved games, players you follow and API keys stay on this device.")
                }
            } footer: {
                Text("Removes this account's games, AI reviews and chats from this device. Saved games, players you follow and API keys stay.")
            }
        }
        // A logout can wait behind a running sync; nothing else starts meanwhile.
        .disabled(isLoggingOut)
        .scrollContentBackground(.hidden)
        .screen("Settings")
        .sheet(isPresented: $showingLinkAccount) {
            LinkAccountView()
        }
    }

    private func logOut() {
        isLoggingOut = true
        Task {
            try? await MatchImportService.logOut(context: modelContext)
            isLoggingOut = false
        }
    }
}
