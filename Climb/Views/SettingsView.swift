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
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About Climb", systemImage: "info.circle")
                }
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

/// Who made the app and where its data and art come from.
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.accent)
                    Text("Climb")
                        .font(.title2.bold())
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Review your League of Legends games, see how you rated against the lobby, and get coaching on what to fix next.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }

            Section("Developer") {
                LabeledContent("Made by", value: "Jialin Wu")
                LabeledContent("Unit", value: "FIT3178, Monash University")
            }

            Section("Data and Services") {
                Link("Riot Games API: accounts, matches, ranks", destination: URL(string: "https://developer.riotgames.com")!)
                Link("Data Dragon: champion, item and rune art", destination: URL(string: "https://developer.riotgames.com/docs/lol#data-dragon")!)
                Link("op.gg: champion tier list and builds", destination: URL(string: "https://op.gg")!)
                Link("Google Gemini: AI coach", destination: URL(string: "https://ai.google.dev")!)
            }

            Section {
                Text("Climb isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games, League of Legends and Teamfight Tactics are trademarks or registered trademarks of Riot Games, Inc.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Legal")
            }
        }
        .scrollContentBackground(.hidden)
        .screen("About")
    }
}
