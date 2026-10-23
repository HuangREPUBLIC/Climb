import SwiftUI

/// An icon whose URL is looked up first (Data Dragon's version, id-to-file maps), then loaded.
/// The one place icons load, so all retry alike: AsyncImage never does, and a scoreboard sees transient failures.
struct RemoteIcon<Placeholder: View>: View {
    let id: AnyHashable
    var contentMode: ContentMode = .fill
    let url: () async -> URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var resolvedURL: URL?
    /// Bumped per retry. A new identity is what makes AsyncImage start over.
    @State private var attempt = 0

    var body: some View {
        Group {
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: contentMode)
                    } else if phase.error != nil {
                        placeholder().task { await retryAfterFailure() }
                    } else {
                        placeholder()
                    }
                }
                .id(attempt)
            } else {
                placeholder()
            }
        }
        .task(id: id) {
            attempt = 0
            resolvedURL = await url()
        }
    }

    private func retryAfterFailure() async {
        guard attempt < 2 else { return }
        try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
        guard !Task.isCancelled else { return }
        let fresh = await url()
        guard !Task.isCancelled else { return }
        // Not swapped through nil: that removes this placeholder, cancelling the very task doing the retry.
        resolvedURL = fresh
        attempt += 1
    }
}

struct ChampionIconView: View {
    let championName: String
    var size: CGFloat = 40

    var body: some View {
        RemoteIcon(id: championName, url: { await DataDragonService.shared.championIconURL(for: championName) }) {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

struct ItemIconView: View {
    let itemID: Int
    var size: CGFloat = 32
    var interactive: Bool = true

    @State private var showingDetail = false

    var body: some View {
        if interactive {
            // A Button, not a tap gesture, for the press feedback and the button trait VoiceOver reads.
            Button { showingDetail = true } label: { icon }
                .buttonStyle(PressableButtonStyle())
                .itemPopover(itemID, isPresented: $showingDetail)
                .accessibilityHint("Shows this item's cost and effect")
        } else {
            icon
        }
    }

    private var icon: some View {
        RemoteIcon(id: itemID, url: { await DataDragonService.shared.itemIconURL(for: itemID) }) {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(.secondary.opacity(0.12))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        // Interactive icons pad their hit area to 44pt (icon untouched); non-interactive ones stay dense.
        .frame(
            minWidth: interactive ? 44 : nil,
            minHeight: interactive ? 44 : nil
        )
        .contentShape(Rectangle())
    }
}

struct ProfileIconView: View {
    let profileIconID: Int
    var size: CGFloat = 32

    var body: some View {
        RemoteIcon(id: profileIconID, url: { await DataDragonService.shared.profileIconURL(for: profileIconID) }) {
            Circle()
                .fill(.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct RuneIconView: View {
    let runeID: Int
    var size: CGFloat = 24

    var body: some View {
        RemoteIcon(id: runeID, contentMode: .fit, url: { await DataDragonService.shared.runeIconURL(for: runeID) }) {
            Circle().fill(.secondary.opacity(0.12))
        }
        .frame(width: size, height: size)
    }
}

struct SpellIconView: View {
    let spellID: Int
    var size: CGFloat = 24

    var body: some View {
        RemoteIcon(id: spellID, url: { await DataDragonService.shared.summonerSpellIconURL(for: spellID) }) {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(.secondary.opacity(0.12))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
