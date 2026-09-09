import SwiftUI
import SwiftData

/// Links the Riot account and chooses which of its games to sync.
///
/// Rebuilt on the app's own card language rather than a `Form`, and with the
/// game picker turned from two bare toggles into rows that say what each game
/// actually is and when it last synced — this sheet is the first screen a new
/// player sees, and a settings-style list gave no sense of what linking does.
struct LinkAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var accounts: [LinkedAccount]

    @State private var gameName = ""
    @State private var tagLine = ""
    @State private var platform: RiotPlatform = .oc1
    @State private var syncLeague = true
    @State private var syncTFT = false
    @State private var isSyncing = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    @ScaledMetric(relativeTo: .title3) private var gameIconSize: CGFloat = 38
    @ScaledMetric(relativeTo: .caption) private var fieldDividerHeight: CGFloat = 20

    private enum Field { case name, tag }

    private var existingAccount: LinkedAccount? { accounts.first }
    private var isFirstLink: Bool { existingAccount == nil }

    private var canSync: Bool {
        !gameName.trimmingCharacters(in: .whitespaces).isEmpty
            && !tagLine.trimmingCharacters(in: .whitespaces).isEmpty
            && (syncLeague || syncTFT)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.sectionSpacing) {
                    if isFirstLink { intro }
                    identityCard
                    gamesCard
                    if let errorMessage { errorCard(errorMessage) }
                    syncButton
                }
                .padding()
                .readableContentWidth()
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isFirstLink ? "Link Riot Account" : "Riot Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    // MARK: - Intro

    /// Only on a first link. Once an account exists this is just a settings
    /// sheet and the explanation is noise.
    private var intro: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Connect your Riot account")
                .font(.headline)
            Text("Climb reads your match history through Riot's public API and keeps it on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Identity

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Riot ID")
                .font(.headline)

            riotIDField

            HStack {
                Label("Server", systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                serverMenu
            }
        }
        .cardSurface()
    }

    /// One control split by a "#", matching how a Riot ID is written — the two
    /// separate rows made the player disassemble their own ID to enter it.
    @ViewBuilder
    private var riotIDField: some View {
        let name = TextField("Game name", text: $gameName)
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit { focusedField = .tag }

        let tag = HStack(spacing: 2) {
            Text("#").foregroundStyle(.tertiary)
            TextField("TAG", text: $tagLine)
                .focused($focusedField, equals: .tag)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
        }

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    name
                    Divider()
                    tag
                }
            } else {
                HStack(spacing: 6) {
                    name
                    Divider().frame(height: fieldDividerHeight)
                    tag.frame(maxWidth: 110, alignment: .leading)
                }
            }
        }
        .font(.body)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private var serverMenu: some View {
        Menu {
            Picker("Server", selection: $platform) {
                ForEach(RiotPlatform.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(platform.displayName)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .scaledFont(9, weight: .semibold)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(0.12))
            .clipShape(Capsule())
        }
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
            Divider()
            unavailableGameRow
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
            HStack(spacing: 12) {
                gameIcon(game, tint: isOn.wrappedValue ? Theme.accent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(game.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    // Once an account exists, when it last synced is the most
                    // useful thing this row can say.
                    Text(lastSyncText(lastSync) ?? caption)
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

    /// Shown rather than hidden: the player can see VALORANT under the same
    /// Riot account, so silently omitting it reads as a missing feature. The
    /// reason it is off is stated in the row itself instead of a form footer.
    private var unavailableGameRow: some View {
        HStack(spacing: 12) {
            gameIcon(.valorant, tint: .secondary)
                .opacity(0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(Game.valorant.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Riot's match endpoints for VALORANT need a production API key, which a personal key doesn't grant.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("VALORANT, unavailable. Riot's match endpoints for VALORANT need a production API key.")
    }

    private func gameIcon(_ game: Game, tint: Color) -> some View {
        Image(systemName: game.systemImageName)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: gameIconSize, height: gameIconSize)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private func lastSyncText(_ date: Date?) -> String? {
        guard let date else { return nil }
        return "Last synced \(date.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Actions

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.loss)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.cardPadding)
        .background(Theme.loss.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .cardShadow()
    }

    /// A full-width button in the sheet body rather than a toolbar item: on a
    /// first link this is the whole point of the screen, and a small "Log In"
    /// in the corner did not read as the primary action.
    private var syncButton: some View {
        VStack(spacing: 8) {
            Button {
                focusedField = nil
                sync()
            } label: {
                HStack(spacing: 8) {
                    if isSyncing {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: isFirstLink ? "link" : "arrow.triangle.2.circlepath")
                    }
                    Text(syncButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(canSync && !isSyncing ? Theme.accent : Color.secondary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canSync || isSyncing)

            if isSyncing {
                Text("Importing matches — this can take a moment on a first sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var syncButtonTitle: String {
        if isSyncing { return "Syncing…" }
        return isFirstLink ? "Link Account" : "Sync Now"
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
                dismiss()
            } catch {
                isSyncing = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
