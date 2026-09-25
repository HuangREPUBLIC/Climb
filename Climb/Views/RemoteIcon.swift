import SwiftUI

/// An icon whose URL has to be looked up first (Data Dragon's version, the
/// id-to-file maps) and then loaded.
///
/// The one place icon loading lives, so every icon recovers the same way.
/// AsyncImage never retries a failed load on its own, and with a scoreboard's
/// worth of icons on screen at once a few transient failures are expected —
/// without a retry each one stays a placeholder for the screen's lifetime.
struct RemoteIcon<Placeholder: View>: View {
    /// Reloads the icon when it changes.
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
        // Not swapped through nil: that removes this placeholder, which
        // cancels the very task doing the retry.
        resolvedURL = fresh
        attempt += 1
    }
}
