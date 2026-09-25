import SwiftUI

/// What keeps costing games across the last 20: the measured signals first,
/// then the AI's read of them. Regenerated only when a new game arrives,
/// since that's the only time the answer can change.
struct TrendDiagnosisCard: View {
    /// The player's own League games, newest first.
    let matches: [Match]

    @AppStorage("trendDiagnosis") private var storedText = ""
    @AppStorage("trendDiagnosisKey") private var storedKey = ""
    @State private var errorMessage: String?

    private var summary: TrendSummary { TrendSummary(matches: matches) }
    private var key: String { "\(matches.first?.id ?? "")|\(summary.games)" }

    var body: some View {
        let summary = summary
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Last \(summary.games) games", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(summary.wins)W \(summary.games - summary.wins)L")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                ForEach(summary.signals) { signal in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signal.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(signal.yours)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(signal.isWeakness ? Theme.loss : .primary)
                            Text(signal.baseline)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
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
            if storedKey != key, summary.games >= 5 { await generate(summary) }
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
