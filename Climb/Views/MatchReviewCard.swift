import SwiftUI
import SwiftData

/// The post-game review (对局复盘): a verdict, the findings that decided the
/// game and one thing to try next — written the first time the match is
/// opened and kept, so the player gets the takeaway without typing a question.
struct MatchReviewCard: View {
    let match: Match
    let allMatches: [Match]

    @Environment(\.modelContext) private var modelContext
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Review", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.accent)

            if let text = match.reviewText {
                CoachReplyView(reply: CoachReply(text))
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await generate() } }
                        .font(.subheadline.weight(.semibold))
                }
            } else {
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
