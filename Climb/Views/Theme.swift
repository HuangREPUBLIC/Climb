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

    /// Always light: a cool off-white page, white cards, and a vivid
    /// blue-violet accent. The cream-and-deep-gold palette before it read as
    /// grey and flat; this one is meant to look like an esports app.
    /// Forced in `ClimbApp`, so these are fixed values, not adaptive.
    static let background = Color(red: 0.965, green: 0.969, blue: 0.984)   // #F6F7FB
    static let surface = Color.white
    static let surfaceRaised = Color(red: 0.933, green: 0.941, blue: 0.969) // #EEF0F7
    static let hairline = Color.black.opacity(0.06)

    /// Indigo #5B5BF6, 4.9:1 on white. Also the root `.tint`, and the
    /// AccentColor asset holds the same value for the tint UIKit draws itself
    /// (alert buttons).
    static let accent = Color(red: 0.357, green: 0.357, blue: 0.965)
    static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)        // #8B5CF6
    /// The selected tab, primary buttons and hero cards.
    static let accentGradient = LinearGradient(
        colors: [accent, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Amber for labels and highlights on the gradient and on dark art.
    static let goldOnDark = Color(red: 0.984, green: 0.749, blue: 0.141)    // #FBBF24
    static let teal = Color(red: 0.024, green: 0.714, blue: 0.831)          // #06B6D4

    /// Image placeholders and the backdrop behind splash art.
    static let navy = Color(red: 0.059, green: 0.071, blue: 0.180)          // #0F122E

    /// Traffic light: saturated, but each still reads as text on white.
    static let good = Color(red: 0.055, green: 0.624, blue: 0.431)          // #0E9F6E
    static let fair = Color(red: 0.851, green: 0.467, blue: 0.024)          // #D97706
    static let poor = Color(red: 0.882, green: 0.114, blue: 0.282)          // #E11D48
    /// For white text on orange, which the system orange is too light for.
    static let orange = Color(red: 0.918, green: 0.345, blue: 0.047)        // #EA580C
    /// Win and loss on the gradient, where the text-on-white shades go muddy.
    static let winBright = Color(red: 0.204, green: 0.827, blue: 0.600)     // #34D399
    static let lossBright = Color(red: 0.984, green: 0.443, blue: 0.522)    // #FB7185

    /// Team colours are semantic, not decorative — they map to the game's
    /// own blue-side / red-side language, so they stay distinct from accent.
    static let ally = Color.blue
    static let enemy = Color.red

    static let win = good
    static let loss = poor

    static let shadow = Color.black.opacity(0.06)

    /// KDA ratio: 3+ is good, under 1 means dying more than helping. Banded
    /// on the two-decimal figure shown, so "3.00" is never yellow.
    static func kdaColor(_ kda: Double) -> Color {
        let shown = (kda * 100).rounded() / 100
        return shown >= 3 ? good : shown >= 1 ? fair : poor
    }
}

extension View {
    /// Standard card surface. Replaces the per-file `sectionCard` helpers that
    /// had each drifted to slightly different padding, radius and shadow.
    func cardSurface(padding: CGFloat = Theme.cardPadding) -> some View {
        self.padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .cardShadow()
    }

    /// A screen's page background and inline title.
    func screen(_ title: String) -> some View {
        background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// A card of rows stacked at the item rhythm — the section body on the match,
/// team and stats screens.
struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.itemSpacing) {
            content
        }
        .cardSurface()
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
        .background(Theme.loss.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .cardShadow()
    }
}

/// What a card says when it has nothing to show yet, in place of zeros or a
/// blank chart that read as broken.
struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    /// 0...1 through the countdown ("3 of 5 games").
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accentGradient)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: progress)
                .tint(Theme.accent)
                .padding(.top, 4)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// A chart legend entry: a coloured dot and its label.
struct LegendDot: View {
    let color: Color
    let label: String

    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 6

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: size, height: size)
            Text(label).scaledFont(10).foregroundStyle(.secondary)
        }
    }
}

/// The full-width gradient button for a screen's main action, with a
/// spinner while it works.
struct PrimaryButton: View {
    let title: String
    var icon: String?
    var isWorking = false
    var isEnabled = true
    var workingNote: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().controlSize(.small).tint(.white)
                    } else if let icon {
                        Image(systemName: icon)
                    }
                    Text(title).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(
                    isEnabled && !isWorking ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.4)),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!isEnabled || isWorking)

            if isWorking, let workingNote {
                Text(workingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
