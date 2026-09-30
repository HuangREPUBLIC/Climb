import SwiftUI

/// One shape scale and one accent for the whole app.
///
/// Before this existed the app mixed six corner radii (3, 5, 8, 10, 12, 14,
/// 18) and picked a different accent per screen — teal charts, a purple
/// profile banner, six differently-tinted stat tiles. Both are the classic
/// "designed by accretion" tells: nothing is wrong in isolation, but the app
/// stops reading as one product.
enum Theme {
    // MARK: - Shape scale

    /// Cards and major containers.
    static let cardRadius: CGFloat = 16
    /// Segmented controls, buttons, inner panels.
    static let controlRadius: CGFloat = 10
    /// Chips, badges, small tiles.
    static let chipRadius: CGFloat = 6

    // MARK: - Spacing rhythm

    static let sectionSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let itemSpacing: CGFloat = 10

    // MARK: - Colour

    /// Always light: cream page, white cards, the League client's gold and
    /// teal as accents. Navy is kept for a few feature cards (`navyGradient`).
    /// Forced in `ClimbApp`, so these are fixed values, not adaptive.
    static let background = Color(red: 0.961, green: 0.953, blue: 0.933)   // #F5F3EE
    static let surface = Color.white
    static let surfaceRaised = Color(red: 0.945, green: 0.937, blue: 0.914) // #F1EFE9
    static let hairline = Color.black.opacity(0.06)

    /// Deep gold #A8863F, dark enough to read on white. Also the root
    /// `.tint`, and the AccentColor asset holds the same value for the tint
    /// UIKit draws itself (alert buttons).
    static let accent = Color(red: 0.659, green: 0.525, blue: 0.247)
    /// The client's own lighter gold, for text on navy.
    static let goldOnDark = Color(red: 0.784, green: 0.667, blue: 0.431)    // #C8AA6E
    static let teal = Color(red: 0.039, green: 0.620, blue: 0.576)          // #0A9E93

    static let navy = Color(red: 0.039, green: 0.078, blue: 0.157)          // #0A1428
    static let navyGradient = LinearGradient(
        colors: [navy, Color(red: 0.102, green: 0.161, blue: 0.259)],      // → #1A2942
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Traffic light. The system green and yellow wash out as text on white,
    /// so these are darkened until they read.
    static let good = Color(red: 0.13, green: 0.60, blue: 0.33)
    static let fair = Color(red: 0.72, green: 0.51, blue: 0.0)
    static let poor = Color(red: 0.85, green: 0.20, blue: 0.20)
    /// For white text on orange, which the system orange is too light for.
    static let orange = Color(red: 0.85, green: 0.42, blue: 0.0)

    /// Team colours are semantic, not decorative — they map to the game's
    /// own blue-side / red-side language, so they stay distinct from accent.
    static let ally = Color.blue
    static let enemy = Color.red

    static let win = good
    static let loss = poor

    /// Charts use the accent rather than a per-screen colour.
    static let chart = accent

    static let shadow = Color.black.opacity(0.06)

    /// KDA ratio: 3+ is good, under 1 means dying more than helping. Banded
    /// on the two-decimal figure shown, so "3.00" is never yellow.
    static func kdaColor(_ kda: Double) -> Color {
        let shown = (kda * 100).rounded() / 100
        return shown >= 3 ? good : shown >= 1 ? fair : poor
    }
}

/// Standard card surface. Replaces the per-file `sectionCard` helpers that
/// had each drifted to slightly different padding, radius and shadow.
struct CardSurface: ViewModifier {
    var padding: CGFloat = Theme.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .cardShadow()
    }
}

extension View {
    func cardSurface(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

// MARK: - Dynamic Type

/// A point size that follows the user's text-size setting.
///
/// `Font.system(size:)` is frozen: it ignores Dynamic Type entirely, so a
/// 9pt label stays 9pt even at the largest accessibility size. Semantic fonts
/// (`.caption2`, `.subheadline`, …) scale correctly and are used wherever one
/// fits, but the scoreboard needs sizes below `.caption2`'s 11pt floor and the
/// match header needs sizes above `.largeTitle`. Those go through here, which
/// scales the point size against a reference style before building the font.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let monospacedDigit: Bool

    init(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        weight: Font.Weight,
        monospacedDigit: Bool
    ) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.monospacedDigit = monospacedDigit
    }

    func body(content: Content) -> some View {
        // No design: the app-wide `.fontDesign(.rounded)` applies.
        let font = Font.system(size: size, weight: weight)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }
}

extension View {
    /// Dynamic-Type-aware replacement for `.font(.system(size:))`.
    /// Prefer a semantic font when one matches; use this only for the sizes
    /// the system ramp doesn't cover.
    func scaledFont(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .caption2,
        weight: Font.Weight = .regular,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(ScaledFont(
            size: size,
            relativeTo: textStyle,
            weight: weight,
            monospacedDigit: monospacedDigit
        ))
    }
}

extension CGFloat {
    /// Icons and badges have to grow with the text they sit beside, but not
    /// without limit — a 44pt portrait at the largest accessibility size is
    /// 150pt wide and leaves nothing for the row it belongs to.
    func capped(at limit: CGFloat) -> CGFloat { Swift.min(self, limit) }
}

// MARK: - Dense content

extension View {
    /// Caps how far a dense data row scales.
    ///
    /// Prose, headings and the profile banner scale over the whole Dynamic
    /// Type range — there is nothing competing for the width. A scoreboard row
    /// or a match row is different: it carries a portrait, an outcome, a KDA
    /// and a timestamp, and at the largest accessibility size one row fills an
    /// entire screen. It technically fits, and it is unusable. So these stop
    /// at the first accessibility size, which is still ~1.6x the default and
    /// still switches them to their stacked layout.
    ///
    /// Apply this at the call site, not inside the row: a view reads
    /// `dynamicTypeSize` from its parent's environment, so a row that clamped
    /// itself would still branch on the unclamped value.
    func denseRowScaling() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

// MARK: - Width

extension Theme {
    /// iPad and landscape hand the app far more width than any of its content
    /// wants. Left to fill it, a match row puts the KDA half a screen away
    /// from the portrait it describes and body text runs past a comfortable
    /// measure. Content is capped at this and centred instead.
    static let contentMaxWidth: CGFloat = 700
}

extension View {
    /// Caps content width and centres it, so the layout reads the same on a
    /// 13" iPad as on a phone instead of stretching to the window.
    ///
    /// This resolves against the *container*, not a `maxWidth` frame, because
    /// a scroll view will happily grow past its own width rather than force a
    /// stubborn child to fit — one un-breakable Riot ID at an accessibility
    /// text size was enough to push a whole screen off both edges. An exact
    /// container-relative width gives every child a hard proposal, so text
    /// wraps or scales instead of overflowing.
    func readableContentWidth(_ maxWidth: CGFloat = Theme.contentMaxWidth) -> some View {
        containerRelativeFrame(.horizontal) { width, _ in
            min(width, maxWidth)
        }
    }
}

/// The elevation every card surface shares.
///
/// `Theme.shadow` was declared from the start and never actually applied, so
/// cards sat flat on the grouped background with nothing separating them from
/// it. Tinted and very soft — the point is that the card reads as a surface,
/// not that the shadow is visible in its own right.
extension View {
    func cardShadow() -> some View {
        shadow(color: Theme.shadow, radius: 10, y: 2)
    }
}

/// A press state for plain buttons.
///
/// `.buttonStyle(.plain)` gives no feedback at all, so a tap on a custom
/// control feels dead. Small and quick — enough to register as a press without
/// becoming an animation the player has to wait out.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A failure message in the page body, where it can't be missed the way a
/// footer line can.
struct ErrorCard: View {
    let message: String

    var body: some View {
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
}
