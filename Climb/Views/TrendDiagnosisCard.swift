import SwiftUI

/// What keeps costing games across the last 20: the measured signals first,
/// then the AI's read of them. Regenerated only when a new game arrives,
/// since that's the only time the answer can change.
struct TrendDiagnosisCard: View {
    /// Built once by the caller, which also gates on its game count.
    let summary: TrendSummary
    /// The newest game: a new one is the only thing that changes the answer.
    let newestID: String?

    @AppStorage("trendDiagnosis") private var storedText = ""
    @AppStorage("trendDiagnosisKey") private var storedKey = ""
    @State private var errorMessage: String?

    private var key: String { "\(newestID ?? "")|\(summary.games)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Last \(summary.games) games", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.accentGradient)
                Spacer()
                Text("\(summary.wins)W \(summary.games - summary.wins)L")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(summary.signals) { signal in
                    ComparisonBarRow(
                        label: signal.label,
                        mine: signal.mine,
                        theirs: signal.theirs,
                        mineLabel: signal.mineLabel,
                        theirsLabel: signal.theirsLabel,
                        digits: signal.digits,
                        mineTint: signal.isWeakness ? Theme.poor : Theme.accent
                    )
                }
            }

            Divider()

            if storedKey == key, !storedText.isEmpty {
                CoachReplyView(reply: CoachReply(storedText))
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await generate(summary) } }
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for patterns…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardSurface()
        .task(id: key) {
            if storedKey != key, summary.games >= TrendSummary.minimumGames { await generate(summary) }
        }
    }

    private func generate(_ summary: TrendSummary) async {
        let requestKey = key
        errorMessage = nil
        do {
            let text = try await CoachService.diagnose(summary, key: requestKey)
            // Superseded by newer games while waiting: that request owns the card.
            guard !Task.isCancelled else { return }
            storedText = text
            storedKey = requestKey
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
