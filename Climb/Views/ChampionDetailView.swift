import SwiftUI

/// One champion in one lane, from op.gg: how it's doing this patch, what to
/// build, which runes, the skill order, and who it beats and loses to.
struct ChampionDetailView: View {
    let champion: String
    let position: OPGGPosition

    @State private var analysis: ChampionAnalysis?
    @State private var tier: Int?
    @State private var errorMessage: String?

    @ScaledMetric(relativeTo: .title2) private var portraitSize: CGFloat = 64
    @ScaledMetric(relativeTo: .caption) private var itemSize: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var skillSize: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                if let analysis {
                    if let stats = analysis.summary?.averageStats {
                        StatSummaryCard(stats: [
                            .init(icon: "percent", tint: stats.winRate >= 0.5 ? Theme.win : Theme.loss, label: "Win rate", value: stats.winRate.formatted(.percent.precision(.fractionLength(0))), tintsValue: true, caption: "Games it wins"),
                            .init(icon: "hand.tap", tint: Theme.teal, label: "Pick rate", value: stats.pickRate.formatted(.percent.precision(.fractionLength(0))), caption: "Games it's picked in"),
                            .init(icon: "nosign", tint: Theme.loss, label: "Ban rate", value: stats.banRate.formatted(.percent.precision(.fractionLength(0))), caption: "Games it's banned in")
                        ])
                    }
                    buildSection(analysis)
                    if let runes = analysis.runes { runesSection(runes) }
                    if let skills = analysis.skills { skillsSection(skills) }
                    matchupsSection(analysis)
                } else if let errorMessage {
                    ErrorCard(message: errorMessage)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
            .readableContentWidth()
        }
        .background(Theme.background)
        .navigationTitle(champion)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tier = await OPGGClient.shared.tier(of: champion, position: position)
        }
        .task {
            do {
                analysis = try await OPGGClient.shared.analysis(champion: champion, position: position)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ChampionIconView(championName: champion, size: portraitSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(champion).font(.title2.bold())
                HStack(spacing: 6) {
                    Text(position.title).font(.subheadline).foregroundStyle(.secondary)
                    // From the lane tier list rather than the analysis reply,
                    // whose grade uses another scale (Malphite: T1 vs T2).
                    if let tier { TierBadge(tier: tier) }
                }
            }
            Spacer()
        }
    }

    // MARK: - Build

    private func buildSection(_ analysis: ChampionAnalysis) -> some View {
        section("Build") {
            if let starter = analysis.starterItems { buildRow("Starter", starter) }
            if let core = analysis.coreItems { buildRow("Core", core) }
            if let boots = analysis.boots { buildRow("Boots", boots) }
            if let spells = analysis.summonerSpells {
                HStack(spacing: 8) {
                    rowLabel("Spells")
                    ForEach(spells.ids, id: \.self) { SpellIconView(spellID: $0, size: itemSize) }
                    Spacer(minLength: 4)
                    rate(spells)
                }
            }
        }
    }

    private func buildRow(_ label: String, _ pick: ChampionAnalysis.Pick) -> some View {
        HStack(spacing: 8) {
            rowLabel(label)
            ForEach(Array(pick.ids.enumerated()), id: \.offset) { index, item in
                if index > 0, label == "Core" {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                // Tappable at full size: this is where a player looks items up.
                ItemIconView(itemID: item, size: itemSize)
            }
            Spacer(minLength: 4)
            rate(pick)
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .leading)
    }

    private func rate(_ pick: ChampionAnalysis.Pick) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(pick.winRate.formatted(.percent.precision(.fractionLength(1))))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(pick.winRate >= 0.5 ? Theme.win : .primary)
            Text("\(pick.play.formatted()) games")
                .scaledFont(9)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Runes

    private func runesSection(_ runes: ChampionAnalysis.Runes) -> some View {
        section("Runes") {
            RuneListView(
                primaryRuneIDs: runes.primaryRuneIds,
                secondaryRuneIDs: runes.secondaryRuneIds,
                primaryStyleID: runes.primaryPageId,
                subStyleID: runes.secondaryPageId,
                statPerkIDs: runes.statModIds,
                alignment: .leading
            )
            rateLine(play: runes.play, win: runes.win)
        }
    }

    // MARK: - Skills

    private func skillsSection(_ skills: ChampionAnalysis.Skills) -> some View {
        section("Skill order") {
            // Level by level, the way the client's level-up prompts arrive.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 9), spacing: 6) {
                ForEach(Array(skills.order.enumerated()), id: \.offset) { index, key in
                    VStack(spacing: 2) {
                        Text(key)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: skillSize, height: skillSize)
                            .background(skillTint(key), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Text("\(index + 1)")
                            .scaledFont(8)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            rateLine(play: skills.play, win: skills.win)
        }
    }

    private func skillTint(_ key: String) -> Color {
        switch key {
        case "Q": return .blue
        case "W": return Theme.good
        case "E": return Theme.orange
        default: return .red
        }
    }

    // MARK: - Matchups

    @ViewBuilder
    private func matchupsSection(_ analysis: ChampionAnalysis) -> some View {
        let strong = analysis.strongCounters ?? []
        let weak = analysis.weakCounters ?? []
        if !strong.isEmpty || !weak.isEmpty {
            section("Matchups") {
                if !strong.isEmpty { counterRow("Strong against", strong) }
                if !strong.isEmpty, !weak.isEmpty { Divider() }
                if !weak.isEmpty { counterRow("Weak against", weak) }
            }
        }
    }

    private func counterRow(_ title: String, _ counters: [ChampionAnalysis.Counter]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(counters) { counter in
                    NavigationLink(value: ChampionRoute(champion: counter.championName, position: position)) {
                        VStack(spacing: 4) {
                            ChampionIconView(championName: counter.championName, size: 40)
                            Text(counter.championName)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(counter.myWinRate.formatted(.percent.precision(.fractionLength(0))))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(counter.myWinRate >= 0.5 ? Theme.win : Theme.loss)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }

    // MARK: - Pieces

    private func rateLine(play: Int, win: Int) -> some View {
        let winRate = play > 0 ? Double(win) / Double(play) : 0
        return Text("\(winRate.formatted(.percent.precision(.fractionLength(1)))) win rate · \(play.formatted()) games")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 12) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }
    }
}
