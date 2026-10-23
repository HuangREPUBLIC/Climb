import SwiftUI
import SwiftData

/// The post-game review (对局复盘): the AI's verdict on top, the game drawn
/// from its real numbers, then the AI's findings as good/bad rows and one
/// thing to try next. The charts never come from the model — only the words
/// do — so nothing on them can be made up. Written the first time the match
/// is opened and kept.
struct MatchReviewCard: View {
    let match: Match
    let allMatches: [Match]

    @Environment(\.modelContext) private var modelContext
    @State private var isGenerating = false
    @State private var errorMessage: String?
    /// Opened, the review ran over two screens and pushed the scoreboard
    /// tabs out of reach; closed it is the verdict and a way in.
    @State private var isExpanded = false

    var body: some View {
        let reply = match.reviewText.map(CoachReply.init)
        VStack(alignment: .leading, spacing: 16) {
            // The rating is in the header right above; not repeated here.
            Label("AI Review", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.accentGradient)

            if let headline = reply?.headline {
                CoachReplyView.styled(headline)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reply {
                // A reply with no headline has nothing to collapse to.
                if isExpanded || reply.headline == nil {
                    ReviewCharts(match: match)
                    // The verdict is already the card's title.
                    CoachReplyView(reply: reply.withoutHeadline)
                }
                if reply.headline != nil {
                    Button {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    } label: {
                        Label(isExpanded ? "Show less" : "Show full review", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            } else if let errorMessage {
                // The charts are drawn from the match, not the model, so a
                // missing key or failed request doesn't take them away.
                ReviewCharts(match: match)
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await generate() } }
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                ReviewCharts(match: match)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reviewing this game…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .task(id: match.id) {
            if match.reviewText == nil { await generate() }
        }
    }

    private func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            try await CoachService.review(match: match, allMatches: allMatches, context: modelContext)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// The game in three pictures: you against the lobby, you against the
/// player in your lane, and how the gold swung.
private struct ReviewCharts: View {
    let match: Match

    @ScaledMetric(relativeTo: .caption) private var radarHeight: CGFloat = 240
    @ScaledMetric(relativeTo: .caption) private var goldChartHeight: CGFloat = 120

    var body: some View {
        if let me = match.focusParticipant {
            VStack(alignment: .leading, spacing: 18) {
                section("You vs the lobby average") {
                    RadarChartView(axes: radarAxes(me), primaryColor: Theme.accent, secondaryColor: .gray)
                        .frame(height: radarHeight)
                    HStack(spacing: 14) {
                        LegendDot(color: Theme.accent, label: "You")
                        LegendDot(color: .gray, label: "Average of the other 9")
                    }
                    .frame(maxWidth: .infinity)
                }

                if let opponent = match.laneOpponent(of: me) {
                    section("You vs your lane opponent, \(opponent.champion)") {
                        VStack(spacing: 12) {
                            ForEach(Self.laneStats, id: \.label) { label, key in
                                ComparisonBarRow(label: label, mine: Double(me[keyPath: key]), theirs: Double(opponent[keyPath: key]),
                                                 theirsLabel: opponent.champion, digits: 0, lowerIsBetter: key == \.deaths)
                            }
                        }
                    }
                }

                if !match.goldTimeline.isEmpty {
                    section("Your team's gold lead") {
                        GoldLeadChart(points: match.goldTimeline)
                            .frame(height: goldChartHeight)
                        Text("Green: your team ahead. Red: behind.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private static let laneStats: [(label: String, key: KeyPath<MatchParticipantSummary, Int>)] = [
        ("Gold earned", \.goldEarned),
        ("Damage to champions", \.damageDealtToChampions),
        ("Minions killed", \.creepScore),
        ("Vision score", \.visionScore),
        ("Deaths", \.deaths)
    ]

    /// Five things a game is won with, each per minute or as a share so a
    /// long game doesn't inflate them. The radar scales each axis to the
    /// larger of the two values.
    private func radarAxes(_ me: MatchParticipantSummary) -> [RadarChartView.Axis] {
        let others = match.participants.filter { $0.puuid != me.puuid }
        func average(_ value: (MatchParticipantSummary) -> Double) -> Double {
            others.isEmpty ? 0 : others.map(value).reduce(0, +) / Double(others.count)
        }
        func perMinute(_ key: KeyPath<MatchParticipantSummary, Int>) -> (MatchParticipantSummary) -> Double {
            { Double($0[keyPath: key]) / match.minutes }
        }
        let axes: [(String, (MatchParticipantSummary) -> Double)] = [
            ("Teamfights", { match.killShare(of: $0) ?? 0 }),
            ("Damage", perMinute(\.damageDealtToChampions)),
            ("Gold", perMinute(\.goldEarned)),
            ("Minions", perMinute(\.creepScore)),
            ("Vision", perMinute(\.visionScore))
        ]
        return axes.map { label, value in
            RadarChartView.Axis(label: label, primaryValue: value(me), secondaryValue: average(value))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .scaledFont(10, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }

}

/// Two bars on one scale — yours and what it's measured against — so who
/// is ahead is a glance rather than a subtraction. Yours is green when
/// clearly better, red when clearly worse, amber when level — the same
/// traffic light as KDA and rating; theirs is always grey.
struct ComparisonBarRow: View {
    let label: String
    let mine: Double
    let theirs: Double
    var mineLabel = "You"
    let theirsLabel: String
    var digits = 1
    /// Deaths: fewer is better.
    var lowerIsBetter = false
    /// Overrides the better/worse colour when the caller has its own verdict.
    var mineTint: Color?

    @ScaledMetric(relativeTo: .caption2) private var nameWidth: CGFloat = 70
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 8

    private var peak: Double { max(mine, theirs, 0.0001) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.semibold))
            bar(mineLabel, value: mine, fraction: mine / peak, tint: mineTint ?? verdictTint, bold: true)
            bar(theirsLabel, value: theirs, fraction: theirs / peak, tint: Color.secondary.opacity(0.3), bold: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(mineLabel) \(format(mine)), \(theirsLabel) \(format(theirs))")
    }

    /// Within 5% reads as level.
    private var verdictTint: Color {
        guard abs(mine - theirs) / peak >= 0.05 else { return Theme.fair }
        return (mine > theirs) != lowerIsBetter ? Theme.good : Theme.poor
    }

    private func bar(_ name: String, value: Double, fraction: Double, tint: Color, bold: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: nameWidth, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(geo.size.width * fraction, barHeight))
            }
            .frame(height: barHeight)
            Text(format(value))
                .font(.caption.weight(bold ? .bold : .regular).monospacedDigit())
                .foregroundStyle(bold ? .primary : .secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    private func format(_ value: Double) -> String {
        digits == 0 ? Int(value.rounded()).formatted() : String(format: "%.\(digits)f", value)
    }
}
