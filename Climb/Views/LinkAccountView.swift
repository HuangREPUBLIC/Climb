import SwiftUI
import SwiftData

/// Syncs or switches the linked Riot account and picks the games to sync; new players use OnboardingView.
struct LinkAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [LinkedAccount]

    @State private var gameName = ""
    @State private var tagLine = ""
    @State private var platform: RiotPlatform = .oc1
    @State private var syncLeague = true
    @State private var syncTFT = false
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var syncSucceeded = false

    @FocusState private var focusedField: RiotIDInput.Field?

    @ScaledMetric(relativeTo: .title3) private var gameIconSize: CGFloat = 38

    private var existingAccount: LinkedAccount? { accounts.first }

    private var canSync: Bool {
        RiotIDInput.isComplete(gameName: gameName, tagLine: tagLine) && (syncLeague || syncTFT)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.sectionSpacing) {
                    identityCard
                    gamesCard
                    if let errorMessage { ErrorCard(message: errorMessage) }
                    syncButton
                }
                .padding()
                .readableContentWidth()
            }
            .screen("Riot Account")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
            // Confirms the outcome by touch as well as sight: the sheet is already dismissing on success.
            .sensoryFeedback(.success, trigger: syncSucceeded)
            .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Riot ID")
                .font(.headline)
            RiotIDInput(gameName: $gameName, tagLine: $tagLine, platform: $platform, focus: $focusedField)
            if isSwitchingAccount {
                Label("This is a different account. Syncing replaces the current match history, AI reviews and notes on this device. Saved games stay.", systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(Theme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardSurface()
    }

    /// The same rule the import uses to drop the old account's games.
    private var isSwitchingAccount: Bool {
        guard let existingAccount, !gameName.isEmpty, !tagLine.isEmpty else { return false }
        return LinkedAccount.identity(gameName: existingAccount.riotGameName, tagLine: existingAccount.riotTagline)
            != LinkedAccount.identity(gameName: gameName, tagLine: tagLine)
    }

    // MARK: - Games

    private var gamesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Games to sync")
                .font(.headline)

            gameRow(
                game: .league,
                caption: "Ranked, draft and Swiftplay matches.",
                lastSync: existingAccount?.lastLeagueSyncDate,
                isOn: $syncLeague
            )
            Divider()
            gameRow(
                game: .tft,
                caption: "Placements and traits from your TFT games.",
                lastSync: existingAccount?.lastTFTSyncDate,
                isOn: $syncTFT
            )
        }
        .cardSurface()
    }

    private func gameRow(
        game: Game,
        caption: String,
        lastSync: Date?,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            let tint = isOn.wrappedValue ? Theme.accent : Color.secondary
            HStack(spacing: 12) {
                Image(systemName: game.systemImageName)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: gameIconSize, height: gameIconSize)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(lastSync.map { "Last synced \($0.formatted(.relative(presentation: .named)))" } ?? caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? Theme.accent : Color.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isOn.wrappedValue ? [.isSelected] : [])
    }

    // MARK: - Actions

    /// A full-width button in the body, not a toolbar item: a corner button didn't read as the primary action.
    private var syncButton: some View {
        PrimaryButton(title: syncButtonTitle, icon: "arrow.triangle.2.circlepath", isWorking: isSyncing, isEnabled: canSync,
                      workingNote: "Importing matches — this can take a moment on a first sync.") {
            focusedField = nil
            sync()
        }
    }

    private var syncButtonTitle: String {
        if isSyncing { return "Syncing…" }
        return isSwitchingAccount ? "Switch Account" : "Sync Now"
    }

    private func prefill() {
        guard let account = existingAccount else { return }
        gameName = account.riotGameName
        tagLine = account.riotTagline
        if let existingPlatform = RiotPlatform(rawValue: account.platform) {
            platform = existingPlatform
        }
        syncLeague = account.syncedGames.contains(.league)
        syncTFT = account.syncedGames.contains(.tft)
    }

    private func sync() {
        errorMessage = nil
        isSyncing = true
        var games: Set<Game> = []
        if syncLeague { games.insert(.league) }
        if syncTFT { games.insert(.tft) }

        Task {
            do {
                try await MatchImportService.linkAndSync(
                    gameName: gameName.trimmingCharacters(in: .whitespaces),
                    tagLine: tagLine.trimmingCharacters(in: .whitespaces),
                    platform: platform,
                    gamesToSync: games,
                    context: modelContext
                )
                isSyncing = false
                syncSucceeded.toggle()
                dismiss()
            } catch {
                isSyncing = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
