import SwiftUI
import SwiftData

/// The Search tab: look up any player by Riot ID and follow the ones you check often.
struct SearchView: View {
    @Query private var accounts: [LinkedAccount]
    @Query(sort: \SavedPlayer.addedAt, order: .reverse) private var savedPlayers: [SavedPlayer]
    @Environment(\.modelContext) private var modelContext

    @State private var gameName = ""
    @State private var tagLine = ""
    @State private var platform: RiotPlatform = .oc1
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var found: FoundPlayer?
    @FocusState private var focusedField: RiotIDInput.Field?

    private struct FoundPlayer: Hashable {
        let puuid: String
        let gameName: String
        let tagLine: String
        let platform: RiotPlatform
    }

    private var canSearch: Bool {
        !isSearching && RiotIDInput.isComplete(gameName: gameName, tagLine: tagLine)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    RiotIDInput(
                        gameName: $gameName,
                        tagLine: $tagLine,
                        platform: $platform,
                        focus: $focusedField,
                        submitLabel: .search,
                        onSubmit: { if canSearch { search() } }
                    )
                    searchButton
                }
                .cardSurface()

                if let errorMessage {
                    ErrorCard(message: errorMessage)
                }

                if !savedPlayers.isEmpty {
                    followingList
                }
            }
            .padding()
            .readableContentWidth()
        }
        .screen("Search")
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(item: $found) { player in
            PlayerProfileView(
                puuid: player.puuid,
                riotIdGameName: player.gameName,
                riotIdTagline: player.tagLine,
                region: player.platform.region,
                platform: player.platform
            )
        }
        .onAppear {
            // Players you follow are usually on your own server.
            if let own = accounts.first.flatMap({ RiotPlatform(rawValue: $0.platform) }), gameName.isEmpty {
                platform = own
            }
        }
        .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
    }

    private var searchButton: some View {
        Button {
            focusedField = nil
            search()
        } label: {
            HStack(spacing: 8) {
                if isSearching {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "magnifyingglass")
                }
                Text(isSearching ? "Searching…" : "Search")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(canSearch ? Theme.accent : Color.secondary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!canSearch)
    }

    /// One-way, like op.gg's favourites: nobody follows back, so it isn't a friends list.
    private var followingList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Following").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(savedPlayers.enumerated()), id: \.element.key) { index, player in
                    if index > 0 { Divider() }
                    NavigationLink {
                        let playerPlatform = RiotPlatform(rawValue: player.platform) ?? platform
                        PlayerProfileView(
                            puuid: nil,
                            riotIdGameName: player.gameName,
                            riotIdTagline: player.tagLine,
                            region: playerPlatform.region,
                            platform: playerPlatform
                        )
                    } label: {
                        HStack {
                            Image(systemName: "person.fill.checkmark").foregroundStyle(Theme.accent)
                            Text(player.riotID).foregroundStyle(.primary)
                            Spacer()
                            Text(RiotPlatform(rawValue: player.platform)?.displayName ?? player.platform)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .contextMenu {
                        Button("Unfollow", systemImage: "person.badge.minus", role: .destructive) {
                            modelContext.delete(player)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .cardSurface(padding: 0)
        }
    }

    /// Resolved here, not on the profile, so a typo is reported beside the field rather than on a pushed screen.
    private func search() {
        let name = gameName.trimmingCharacters(in: .whitespaces)
        let tag = tagLine.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        errorMessage = nil
        isSearching = true
        Task {
            defer { isSearching = false }
            do {
                let puuid = try await RiotAPIClient.shared.resolvePUUID(gameName: name, tagLine: tag, region: platform.region)
                found = FoundPlayer(puuid: puuid, gameName: name, tagLine: tag, platform: platform)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
