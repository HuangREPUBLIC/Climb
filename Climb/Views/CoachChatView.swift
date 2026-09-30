import SwiftUI
import SwiftData

/// The conversational coach.
///
/// Three things make this readable rather than a wall of text: the match it is
/// about is pinned at the top so the thread has a subject, coach replies are
/// parsed into a verdict / findings / one action instead of being printed raw
/// (see `CoachReplyView`), and follow-up questions are always one tap away
/// rather than something the player has to think up and type.
struct CoachChatView: View {
    @Bindable var match: Match
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]

    @State private var conversation: CoachConversation?
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var typingPhase = false

    @ScaledMetric(relativeTo: .caption2) private var avatarSize: CGFloat = 28
    @ScaledMetric(relativeTo: .caption2) private var typingDotSize: CGFloat = 6
    @ScaledMetric(relativeTo: .subheadline) private var sendButtonSize: CGFloat = 34

    /// Openers before the first reply, follow-ups after — a chip row that keeps
    /// offering "what went wrong" once that has been answered is dead weight.
    private var promptSuggestions: [String] {
        sortedMessages.isEmpty
            ? ["What went wrong in this game?", "What should I build next time?", "How's my recent form?"]
            : ["Why?", "What should I have done instead?", "Is this a pattern?", "How do I practise that?"]
    }

    private var sortedMessages: [ChatMessage] {
        (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        CoachMatchSnapshot(match: match)

                        if sortedMessages.isEmpty {
                            emptyState
                        }

                        ForEach(sortedMessages) { message in
                            bubble(for: message)
                                .id(message.persistentModelID)
                        }

                        if isSending {
                            typingIndicator
                        }
                    }
                    .padding()
                    .readableContentWidth()
                }
                .onChange(of: sortedMessages.count) {
                    guard let last = sortedMessages.last else { return }
                    withAnimation(.snappy(duration: 0.28)) {
                        proxy.scrollTo(last.persistentModelID, anchor: .bottom)
                    }
                }
            }

            if let errorMessage {
                errorBar(errorMessage)
            }

            composer
        }
        .background(Theme.background)
        .navigationTitle("AI Coach")
        // A conversation wants the full height for the input bar.
        .hidesTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            conversation = CoachService.conversation(for: match, context: modelContext)
        }
    }

    // MARK: - Messages

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                coachAvatar
                Text("Ask about this game")
                    .font(.subheadline.weight(.semibold))
            }
            Text("The coach can see this match's stats, items, your notes and your tags — and how it compares to your recent games.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        // Each side indents away from the opposite edge so the thread reads as
        // a conversation rather than two stacked columns of full-width text.
        HStack(alignment: .top, spacing: 8) {
            if message.role == .coach {
                coachAvatar
            } else {
                Spacer(minLength: 44)
            }

            Group {
                if message.role == .coach {
                    CoachReplyView(reply: CoachReply(message.text))
                } else {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                message.role == .player
                    ? AnyShapeStyle(Theme.accent)
                    : AnyShapeStyle(Theme.surface)
            )
            .clipShape(bubbleShape(for: message.role))
            .overlay(
                // A hairline, not a shadow: these sit on a grouped background
                // where a shadow reads as clutter, but the coach bubble still
                // needs an edge to separate it from the surface behind it.
                bubbleShape(for: message.role)
                    .strokeBorder(
                        message.role == .coach ? Color.primary.opacity(0.06) : .clear,
                        lineWidth: 1
                    )
            )

            if message.role == .coach {
                Spacer(minLength: 20)
            }
        }
    }

    private func bubbleShape(for role: ChatRole) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Theme.cardRadius,
            bottomLeadingRadius: role == .coach ? 4 : Theme.cardRadius,
            bottomTrailingRadius: role == .player ? 4 : Theme.cardRadius,
            topTrailingRadius: Theme.cardRadius,
            style: .continuous
        )
    }

    private var coachAvatar: some View {
        Circle()
            .fill(Theme.accent.opacity(0.15))
            .frame(width: avatarSize, height: avatarSize)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
    }

    /// Three dots breathing in sequence. A static row of dots reads as a
    /// rendering glitch; the movement is what says "still thinking".
    private var typingIndicator: some View {
        HStack(alignment: .top, spacing: 8) {
            coachAvatar
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: typingDotSize, height: typingDotSize)
                        .opacity(typingPhase ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: typingPhase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .clipShape(bubbleShape(for: .coach))
            Spacer(minLength: 20)
        }
        .onAppear { typingPhase = true }
        .onDisappear { typingPhase = false }
        .accessibilityLabel("Coach is replying")
    }

    private func errorBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(Theme.loss)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.loss.opacity(0.1))
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            // Suggestions stay available for the whole conversation, because
            // "ask a follow-up" is the feature — making the player compose one
            // from scratch every time is what turns a chat into a search box.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(promptSuggestions, id: \.self) { prompt in
                        Button {
                            draft = prompt
                            send()
                        } label: {
                            Text(prompt)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the coach…", text: $draft, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(Capsule())

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: sendButtonSize, height: sendButtonSize)
                        .background(canSend ? Theme.accent : Color.secondary.opacity(0.4))
                        .clipShape(Circle())
                        // The circle stays 34pt for balance against the field,
                        // but the tappable area is a full 44.
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private func send() {
        guard let conversation else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        errorMessage = nil
        isSending = true
        Task {
            do {
                try await CoachService.send(
                    userMessage: text,
                    conversation: conversation,
                    match: match,
                    allMatches: allMatches,
                    context: modelContext
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                // Hand the question back so a retry is one tap, not retyping.
                if draft.isEmpty { draft = text }
            }
            isSending = false
        }
    }
}
