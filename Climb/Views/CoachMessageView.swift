import SwiftUI

/// A coach reply, split into the parts the UI can actually lay out.
///
/// The model is asked for a verdict line, a few bullets and an optional action
/// (see `CoachService.buildSystemPrompt`), but an LLM will not always comply —
/// so parsing is lenient and anything unrecognised falls through to `body` and
/// renders as ordinary prose. A reply that doesn't match the shape must still
/// be readable, just less structured.
struct CoachReply {
    var headline: String?
    var bullets: [String] = []
    var action: String?
    var body: [String] = []

    var isStructured: Bool { !bullets.isEmpty || action != nil }

    init(_ raw: String) {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            if let bullet = Self.bulletBody(of: line) {
                bullets.append(bullet)
            } else if let action = Self.actionBody(of: line) {
                self.action = action
            } else if headline == nil, bullets.isEmpty, line.count <= 140 {
                // Only the opening line is treated as a verdict, and only when
                // it is short — a long first paragraph is prose, not a headline.
                headline = Self.stripMarkers(line)
            } else {
                body.append(line)
            }
        }

        if headline == nil, bullets.isEmpty, action == nil {
            body = lines
        }
    }

    private static func bulletBody(of line: String) -> String? {
        for marker in ["- ", "• ", "* ", "– "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func actionBody(of line: String) -> String? {
        for prefix in ["Try:", "Next game:", "Try next game:", "Action:"] {
            if line.lowercased().hasPrefix(prefix.lowercased()) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Models like to bold or head their verdict line; the styling is the UI's
    /// job, so the markers come off.
    private static func stripMarkers(_ line: String) -> String {
        var text = line
        while text.hasPrefix("#") { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// Renders a parsed coach reply: a verdict, findings as scannable rows, and the
/// one thing to do differently as a distinct strip.
///
/// The point is that a player skims. A paragraph asks them to read the whole
/// thing to find the advice; rows put the advice where the eye lands first.
struct CoachReplyView: View {
    let reply: CoachReply

    @ScaledMetric(relativeTo: .caption) private var markerSize: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let headline = reply.headline {
                styled(headline)
                    .font(reply.isStructured ? .subheadline.weight(.semibold) : .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !reply.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(reply.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: markerSize, height: markerSize)
                                // A dot sits optically low on a text baseline;
                                // nudging it up aligns it with the x-height.
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            styled(bullet)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            ForEach(Array(reply.body.enumerated()), id: \.offset) { _, paragraph in
                styled(paragraph)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action = reply.action {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "target")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT GAME")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.accent)
                        styled(action)
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.1))
                // Concentric with the bubble: the bubble's radius less its own
                // padding, so the two curves stay optically parallel.
                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            }
        }
    }

    /// Inline markdown only — the coach writes `**bold**`, and stray asterisks
    /// leaking into the bubble is exactly the "wall of text" look.
    private func styled(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}

/// The match the conversation is about, pinned above it.
///
/// Without this the coach screen opens on blank space and the player has to
/// remember which game they tapped. These are also exactly the stats the coach
/// was given, so its answers are checkable against something on screen rather
/// than taken on faith.
struct CoachMatchSnapshot: View {
    let match: Match

    @ScaledMetric(relativeTo: .subheadline) private var portraitSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let stats = match.leagueStats {
                    ChampionIconView(championName: stats.champion, size: portraitSize)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.win ? "Victory" : "Defeat")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(match.win ? Theme.win : Theme.loss)
                    Text(subtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 6)

                if let score = PerformanceScore.compute(for: match) {
                    Text(String(format: "%.1f", score))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(PerformanceScore.color(for: score))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PerformanceScore.color(for: score).opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
            }

            // The player's own tags, shown here because the coach is given them
            // too — it makes visible what the answer is actually grounded in.
            if !match.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(match.tags, id: \.self) { tag in
                        TagChip(text: tag)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .cardShadow()
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if let stats = match.leagueStats {
            return "\(stats.champion) · \(stats.kills)/\(stats.deaths)/\(stats.assists) · \(stats.role)"
        }
        if let stats = match.tftStats {
            return "TFT · placed #\(stats.placement)"
        }
        return match.queueType
    }
}
