import SwiftUI

/// One game as its own card, written for someone who doesn't play: kills,
/// deaths and assists are spelled out, and the build is cut to the three items
/// that cost the most. Spells, runes, the full build and the accolades live in
/// the long-press preview (`MatchPreviewView`).
struct MatchRowView: View {
    let match: Match

    @ScaledMetric(relativeTo: .headline) private var rawPortraitSize: CGFloat = 56
    private var portraitSize: CGFloat { rawPortraitSize.capped(at: 84) }
    @ScaledMetric(relativeTo: .caption) private var itemSize: CGFloat = 30

    /// The three most expensive build items, once Data Dragon's prices load.
    @State private var coreItems: [Int]?

    private var resultColor: Color { match.resultColor }
    /// Build slots 0-5, empties dropped; slot 6 is the trinket.
    private var build: [Int] { (match.leagueStats?.items ?? []).prefix(6).filter { $0 != 0 } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                portrait
                OutcomePill(text: match.outcomeText, tint: resultColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.leagueStats?.champion ?? "Teamfight Tactics")
                            .font(.headline)
                            .lineLimit(1)
                        queueLine
                    }
                    Spacer(minLength: 4)
                    if let stats = match.leagueStats { KDABadge(kda: stats.kda) }
                    RatingBadge(match: match)
                }

                if let stats = match.leagueStats {
                    // K/D/A and the build on one row, so a card is two lines
                    // of text rather than three; stacked when they don't fit.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 4) {
                            KDAColumns(stats: stats, showsRatio: false, spacing: 10)
                            Spacer(minLength: 4)
                            itemRow
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            KDAColumns(stats: stats, showsRatio: false, spacing: 10)
                            itemRow
                        }
                    }
                } else if let tft = match.tftStats {
                    Text("Level \(tft.level) · \(tft.traits.prefix(3).joined(separator: " · "))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only the strip and the pill carry the result: a whole-card wash
        // turned a losing streak into a screen of pink.
        .background(alignment: .leading) {
            resultColor.frame(width: 4)
        }
        .cardSurface(padding: 0)
        .accessibilityElement(children: .combine)
        .task(id: match.id) {
            guard coreItems == nil else { return }
            let build = build
            let cost = await DataDragonService.shared.itemCosts(build)
            coreItems = Self.core(of: build) { cost[$0] ?? 0 }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var portrait: some View {
        if let stats = match.leagueStats {
            ChampionIconView(championName: stats.champion, size: portraitSize)
                .clipShape(RoundedRectangle(cornerRadius: portraitSize * 0.22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: portraitSize * 0.22, style: .continuous).strokeBorder(resultColor.opacity(0.7), lineWidth: 2))
        } else if let tft = match.tftStats {
            RoundedRectangle(cornerRadius: portraitSize * 0.22, style: .continuous)
                .fill(resultColor.opacity(0.15))
                .frame(width: portraitSize, height: portraitSize)
                .overlay {
                    Text("#\(tft.placement)")
                        .font(.title2.bold())
                        .foregroundStyle(resultColor)
                }
        }
    }

    private var queueLine: some View {
        let style = ChipStyle.of(match.queueType)
        // The list's day headers carry the date; the time places it in the
        // day, and is the part dropped when KDA, MVP and rating crowd the row.
        let time = match.timestamp.formatted(date: .omitted, time: .shortened)
        return ViewThatFits(in: .horizontal) {
            queueLabel("\(match.queueType) · \(time)", style: style)
            queueLabel(match.queueType, style: style)
        }
        .font(.caption)
    }

    private func queueLabel(_ text: String, style: (tint: Color, icon: String)) -> some View {
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .foregroundStyle(style.tint)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private var itemRow: some View {
        let shown = coreItems ?? []
        // Tappable for the item bubble. Each icon's hit area is padded out to
        // 44pt, which already spaces them apart; the first is pulled back so
        // the icon itself lines up with the text above. Blank slots hold the
        // row's height until prices pick which three to show.
        return HStack(spacing: 0) {
            if coreItems == nil {
                ForEach(0..<min(build.count, 3), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: itemSize * 0.2)
                        .fill(.secondary.opacity(0.08))
                        .frame(width: itemSize, height: itemSize)
                        .frame(width: 44, height: 44)
                }
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { index, item in
                ItemIconView(itemID: item, size: itemSize)
                    // The rest of the build as a corner badge, not a column:
                    // the row has to fit beside K/D/A.
                    .overlay(alignment: .topTrailing) {
                        if index == shown.count - 1, build.count > 3 {
                            Text("+\(build.count - 3)")
                                .scaledFont(9, weight: .bold, monospacedDigit: true)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary, in: Capsule())
                                // Anchored to the 44pt hit frame; pulled in to the icon's corner.
                                .offset(x: -max(44 - itemSize, 0) / 2 + 4, y: max(44 - itemSize, 0) / 2 - 4)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(.leading, min(itemSize - 44, 0) / 2)
    }

    /// The `count` priciest items of a build, kept in slot order.
    static func core(of build: [Int], count: Int = 3, cost: (Int) -> Int) -> [Int] {
        build.indices
            .sorted { cost(build[$0]) > cost(build[$1]) }
            .prefix(count)
            .sorted()
            .map { build[$0] }
    }

    #if DEBUG
    static func selfCheck() {
        let prices = [1: 300, 2: 3000, 3: 1100, 4: 3200, 5: 2800]
        assert(core(of: [1, 2, 3, 4, 5]) { prices[$0]! } == [2, 4, 5], "core items: priciest three, slot order")
        assert(core(of: [1]) { prices[$0]! } == [1], "core items: short build kept whole")
        assert(Theme.kdaColor(3) == Theme.good && Theme.kdaColor(2.9) == Theme.fair && Theme.kdaColor(0.9) == Theme.poor, "KDA bands")
        assert(Theme.kdaColor(2.999) == Theme.good, "KDA colour follows the printed 3.00")
        assert(PerformanceScore.color(for: 6) == Theme.good && PerformanceScore.color(for: 5.9) == Theme.fair
               && PerformanceScore.color(for: 3.9) == Theme.poor, "rating bands")
        assert(PerformanceScore.color(for: 3.96) == Theme.fair, "rating colour follows the printed 4.0")
    }
    #endif
}

// MARK: - Shared pieces

extension Match {
    /// TFT's `win` is a top-4 finish, set at import.
    var outcomeText: String {
        tftStats != nil ? (win ? "TOP 4" : "BOTTOM 4") : (win ? "VICTORY" : "DEFEAT")
    }

    var resultColor: Color { win ? Theme.win : Theme.loss }
}

/// A champion's splash art under a bottom-heavy scrim, behind light text.
/// Pair with `.environment(\.colorScheme, .dark)` on the text.
struct ChampionSplash: View {
    let champion: String?

    var body: some View {
        ZStack {
            if let champion, let url = DataDragonService.shared.splashArtURL(for: champion) {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Theme.navy }
            } else {
                Theme.navy
            }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// "VICTORY" / "DEFEAT" under the portrait.
private struct OutcomePill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .scaledFont(9, weight: .heavy)
            .tracking(0.5)
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// The 0-10 rating, labelled, in its traffic-light colour — with MVP / SVP
/// beside it when the player earned one.
struct RatingBadge: View {
    let match: Match

    var body: some View {
        if let score = PerformanceScore.compute(for: match) {
            let awards = PerformanceScore.awards(in: match)
            let award = match.focusParticipant.flatMap { MatchAward(puuid: $0.puuid, awards: awards) }
            let tint = PerformanceScore.color(for: score)
            HStack(spacing: 5) {
                if let award {
                    Text(award.text)
                        .scaledFont(9, weight: .black)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(award.tint, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", score))
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                    Text("RATING")
                        .scaledFont(7, weight: .bold)
                        .tracking(0.4)
                        .opacity(0.8)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rating \(String(format: "%.1f", score)) out of 10\(award.map { ", \($0.text)" } ?? "")")
        }
    }
}

/// The KDA ratio in the rating badge's shape, so the card's two verdicts
/// sit side by side and read the same way.
struct KDABadge: View {
    let kda: Double

    var body: some View {
        let tint = Theme.kdaColor(kda)
        VStack(spacing: 0) {
            Text(String(format: "%.2f", kda))
                .font(.subheadline.weight(.heavy).monospacedDigit())
            Text("KDA")
                .scaledFont(7, weight: .bold)
                .tracking(0.4)
                .opacity(0.8)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KDA \(String(format: "%.2f", kda))")
    }
}

/// Kills, deaths and assists as labelled columns, then the KDA ratio in its
/// traffic-light colour — "5 / 8 / 7" means nothing to someone who doesn't play.
struct KDAColumns: View {
    let stats: LeagueStats
    /// The match card shows the ratio as a badge beside the rating instead.
    var showsRatio = true
    var spacing: CGFloat = 14

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            column("\(stats.kills)", "KILLS", .primary)
            column("\(stats.deaths)", "DEATHS", Theme.loss)
            column("\(stats.assists)", "ASSISTS", .primary)
            if showsRatio {
                Spacer(minLength: 4)
                column(String(format: "%.2f", stats.kda), "KDA", Theme.kdaColor(stats.kda), alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats.kills) kills, \(stats.deaths) deaths, \(stats.assists) assists" + (showsRatio ? ", KDA \(String(format: "%.2f", stats.kda))" : ""))
    }

    private func column(_ value: String, _ label: String, _ tint: Color, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .scaledFont(8, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - List

/// The match list both profiles use — your own history and a searched
/// player's — so the two can't drift apart. Tap opens the match; long-press
/// peeks at it.
struct MatchCardList: View {
    let matches: [Match]
    let open: (Match) -> Void
    /// Only for your own games; tags on someone else's game go nowhere.
    var editTags: ((Match) -> Void)?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            // Day headers: "2 wk. ago" on every card said nothing about
            // which games were one evening's session.
            ForEach(Self.days(of: matches)) { day in
                Section {
                    ForEach(day.matches) { card($0) }
                } header: {
                    dayHeader(day)
                }
            }
        }
    }

    private func dayHeader(_ day: DayGroup) -> some View {
        let wins = day.matches.filter(\.win).count
        return HStack(spacing: 6) {
            Text(Self.title(for: day.date))
                .font(.subheadline.weight(.semibold))
            Text("\(wins)W \(day.matches.count - wins)L")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    struct DayGroup: Identifiable {
        let date: Date
        var matches: [Match]
        var id: Date { date }
    }

    /// Games by calendar day, days in first-seen order. Bucketed rather than
    /// split on runs: a searched player's list follows Riot's id order, and
    /// two runs of one day would give the ForEach a duplicate id.
    static func days(of matches: [Match]) -> [DayGroup] {
        var groups: [DayGroup] = []
        var index: [Date: Int] = [:]
        for match in matches {
            let date = Calendar.current.startOfDay(for: match.timestamp)
            if let i = index[date] {
                groups[i].matches.append(match)
            } else {
                index[date] = groups.count
                groups.append(DayGroup(date: date, matches: [match]))
            }
        }
        return groups
    }

    static func title(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let format = Date.FormatStyle.dateTime.weekday(.wide).month(.abbreviated).day()
        // Loading older games can reach last year, where "Tuesday, Oct 14" is ambiguous.
        return date.formatted(Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) ? format : format.year())
    }

    private func card(_ match: Match) -> some View {
        Button { open(match) } label: { MatchRowView(match: match) }
            .buttonStyle(PressableButtonStyle())
            .contextMenu {
                Button("View details", systemImage: "arrow.up.forward.square") { open(match) }
                if let editTags {
                    Button("Add tag", systemImage: "tag") { editTags(match) }
                }
            } preview: {
                MatchPreviewView(match: match)
            }
    }
}

// MARK: - Preview

/// The long-press peek: everything the card leaves out.
struct MatchPreviewView: View {
    let match: Match

    private var me: MatchParticipantSummary? { match.focusParticipant }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let stats = match.leagueStats {
                VStack(alignment: .leading, spacing: 16) {
                    KDAColumns(stats: stats)
                    loadout(stats)
                    statGrid(stats)
                    if !accolades.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(accolades, id: \.text) { accolade in
                                Label {
                                    Text(accolade.text)
                                } icon: {
                                    Image(systemName: accolade.icon).foregroundStyle(.orange)
                                }
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
                .padding(16)
            } else if let tft = match.tftStats {
                Text("Level \(tft.level) · \(tft.traits.joined(separator: " · "))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .frame(width: 360)
        .background(Theme.surface)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.outcomeText)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(match.resultColor)
                Text(match.leagueStats?.champion ?? "Teamfight Tactics")
                    .font(.headline)
                Text("\(match.queueType) · \(match.gameDurationSeconds / 60)m \(match.gameDurationSeconds % 60)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RatingBadge(match: match)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .bottomLeading)
        .background { ChampionSplash(champion: match.leagueStats?.champion) }
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    /// Spells and runes, then all seven item slots.
    private func loadout(_ stats: LeagueStats) -> some View {
        HStack(spacing: 4) {
            ForEach(stats.summonerSpellIDs, id: \.self) { SpellIconView(spellID: $0, size: 26) }
            ForEach([stats.keystoneID, stats.subStyleID].filter { $0 != 0 }, id: \.self) { RuneIconView(runeID: $0, size: 26) }
            Divider().frame(height: 22).padding(.horizontal, 4)
            ItemSlots(items: stats.items, size: 26, spacing: 4)
        }
    }

    private func statGrid(_ stats: LeagueStats) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                tile("Minions", "\(stats.creepScore)", String(format: "%.1f / min", Double(stats.creepScore) / match.minutes))
                tile("Damage", Self.compact(stats.damageDealtToChampions), "to champions")
            }
            GridRow {
                tile("Gold", Self.compact(stats.goldEarned), "earned")
                tile("Vision", "\(stats.visionScore)", "\(stats.wardsPlaced) wards placed")
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .scaledFont(9, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    static func compact(_ value: Int) -> String {
        value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : "\(value)"
    }

    // MARK: Accolades

    /// Only the genuinely uncommon: multi-kills start at triple, and "most"
    /// needs a real margin over the runner-up.
    private var accolades: [(text: String, icon: String)] {
        guard let stats = match.leagueStats else { return [] }
        var result: [(text: String, icon: String)] = []
        if stats.pentaKills > 0 { result.append(("Pentakill", "flame.fill")) }
        else if stats.quadraKills > 0 { result.append(("Quadra Kill", "flame.fill")) }
        else if stats.tripleKills > 0 { result.append(("Triple Kill", "flame.fill")) }
        if stats.firstBloodKill { result.append(("First Blood", "drop.fill")) }
        if let me {
            if leads(\.damageDealtToChampions, me: me, byMargin: 1.15) { result.append(("Most Damage", "burst.fill")) }
            if leads(\.damageTaken, me: me, byMargin: 1.25) { result.append(("Most Tanked", "shield.fill")) }
        }
        return result
    }

    /// True when the player tops every other player on `metric` by at least
    /// `margin` (1.15 = 15% clear of second place).
    private func leads(_ metric: KeyPath<MatchParticipantSummary, Int>, me: MatchParticipantSummary, byMargin margin: Double) -> Bool {
        let mine = me[keyPath: metric]
        guard mine > 0 else { return false }
        let runnerUp = match.participants.filter { $0.puuid != me.puuid }.map { $0[keyPath: metric] }.max() ?? 0
        return Double(mine) >= Double(runnerUp) * margin
    }
}
