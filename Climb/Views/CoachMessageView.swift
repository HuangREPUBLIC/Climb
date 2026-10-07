import SwiftUI

/// A coach reply, split into the parts the UI can actually lay out.
///
/// The model is asked for a verdict line, a few bullets and an optional action
/// (see `CoachService.buildSystemPrompt`), but an LLM will not always comply —
/// so parsing is lenient and anything unrecognised falls through to `body` and
/// renders as ordinary prose. A reply that doesn't match the shape must still
/// be readable, just less structured.
struct CoachReply {
    /// One finding. The model tags each with `[+area]` (went well) or
    /// `[-area]` (cost the game); an untagged bullet — a chat reply, or a
    /// review cached before tags existed — has no verdict and no area.
    struct Finding: Equatable {
        /// The areas the prompt offers, each with its icon.
        enum Area: String, CaseIterable {
            case lane, farm, fight, death, vision, objective, gold, damage

            var symbol: String {
                switch self {
                case .lane: "arrow.left.arrow.right"
                case .farm: "leaf.fill"
                case .fight: "flame.fill"
                case .death: "heart.slash.fill"
                case .vision: "eye.fill"
                case .objective: "flag.fill"
                case .gold: "dollarsign.circle.fill"
                case .damage: "burst.fill"
                }
            }
        }

        var text: String
        var isPositive: Bool?
        var area: String?

        init(_ line: String) {
            text = line
            // Models bold the tag or use full-width brackets and a real minus.
            var tagged = line.trimmingCharacters(in: Self.decoration)
            for (from, to) in [("［", "["), ("【", "["), ("］", "]"), ("】", "]"), ("−", "-"), ("–", "-"), ("＋", "+")] {
                tagged = tagged.replacingOccurrences(of: from, with: to)
            }
            guard tagged.hasPrefix("["), let close = tagged.firstIndex(of: "]") else { return }
            let tag = tagged[tagged.index(after: tagged.startIndex)..<close]
            guard let sign = tag.first, sign == "+" || sign == "-" else { return }
            let area = tag.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
            // "[-500 gold] at 15" in a chat reply is a number, not a tag.
            guard area.isEmpty || area.allSatisfy(\.isLetter) else { return }
            isPositive = sign == "+"
            self.area = area.isEmpty ? nil : area
            text = tagged[tagged.index(after: close)...].trimmingCharacters(in: Self.decoration)
        }

        private static let decoration = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "*_`"))
    }

    var headline: String?
    var bullets: [Finding] = []
    var action: String?
    var body: [String] = []

    var isStructured: Bool { !bullets.isEmpty || action != nil }

    /// For a card that shows the verdict as its own title.
    var withoutHeadline: CoachReply {
        var copy = self
        copy.headline = nil
        return copy
    }

    init(_ raw: String) {
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            if let bullet = Self.bulletBody(of: line) {
                bullets.append(Finding(bullet))
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

    #if DEBUG
    static func selfCheck() {
        let reply = CoachReply("Lost lane, won the game.\n- [-death] 9 deaths, lobby 6.2\n- [+ fight] 72% kill share\n- plain bullet\nTry: ward before you duel")
        assert(reply.headline == "Lost lane, won the game.", "verdict line")
        assert(reply.bullets == [
            Finding("[-death] 9 deaths, lobby 6.2"),
            Finding("[+ fight] 72% kill share"),
            Finding("plain bullet")
        ], "bullets kept in order")
        assert(reply.bullets[0].isPositive == false && reply.bullets[0].area == "death" && reply.bullets[0].text == "9 deaths, lobby 6.2", "negative tag")
        assert(reply.bullets[1].isPositive == true && reply.bullets[1].area == "fight", "positive tag, space tolerated")
        assert(reply.bullets[2].isPositive == nil && reply.bullets[2].text == "plain bullet", "untagged bullet unchanged")
        assert(Finding("[note] x").isPositive == nil && Finding("[note] x").text == "[note] x", "non-verdict bracket left alone")
        assert(reply.action == "ward before you duel", "action line")
        assert(Finding("**[-vision]** 0.6 per minute").area == "vision" && Finding("**[-vision]** 0.6 per minute").text == "0.6 per minute", "bolded tag")
        assert(Finding("［−视野］ 视野不足").isPositive == false && Finding("［−视野］ 视野不足").area == "视野", "full-width brackets, real minus")
        assert(Finding("[-500 gold] at 15").isPositive == nil, "a number in brackets is not a tag")
    }
    #endif

    private static func bulletBody(of line: String) -> String? {
        for marker in ["- ", "• ", "* ", "– "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func actionBody(of line: String) -> String? {
        // The model is told to keep "Try:" in any language, but a Chinese
        // reply sometimes translates it anyway.
        for prefix in ["Try:", "Next game:", "Try next game:", "Action:", "建议：", "建议:", "尝试：", "尝试:", "下局："] {
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
    @ScaledMetric(relativeTo: .subheadline) private var verdictIconSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let headline = reply.headline {
                Self.styled(headline)
                    .font(reply.isStructured ? .subheadline.weight(.semibold) : .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !reply.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(reply.bullets.enumerated()), id: \.offset) { _, bullet in
                        if bullet.isPositive != nil {
                            verdictRow(bullet)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: markerSize, height: markerSize)
                                    // A dot sits optically low on a text baseline;
                                    // nudging it up aligns it with the x-height.
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                Self.styled(bullet.text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            ForEach(Array(reply.body.enumerated()), id: \.offset) { _, paragraph in
                Self.styled(paragraph)
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
                        Self.styled(action)
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

    /// A tagged finding: the area's icon on a green or red tile, then the
    /// sentence on a tint of the same colour — good and bad sort themselves
    /// at a glance, before a word is read.
    private func verdictRow(_ finding: CoachReply.Finding) -> some View {
        let good = finding.isPositive == true
        let tint = good ? Theme.good : Theme.poor
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.area.flatMap(CoachReply.Finding.Area.init(rawValue:))?.symbol ?? (good ? "checkmark" : "xmark"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: verdictIconSize, height: verdictIconSize)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Self.styled(finding.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: verdictIconSize, alignment: .leading)
        }
        .padding(8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(good ? "Went well" : "Cost you"): \(finding.text)")
    }

    /// Inline markdown only — the coach writes `**bold**`, and stray asterisks
    /// leaking into the bubble is exactly the "wall of text" look.
    /// Also used for the review card's verdict title.
    static func styled(_ text: String) -> Text {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 12)
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
