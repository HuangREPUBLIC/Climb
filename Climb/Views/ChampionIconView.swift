import SwiftUI

struct ChampionIconView: View {
    let championName: String
    var size: CGFloat = 40

    @State private var iconURL: URL?
    @State private var retryCount = 0

    private static let maxRetries = 2

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        // AsyncImage never retries a failed load on its own. With
                        // this many icons on screen at once, a handful of
                        // transient failures are expected, so give each a couple
                        // of chances to self-heal instead of staying a
                        // placeholder for the rest of the screen's lifetime.
                        placeholder.task { await retryAfterFailure() }
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .task(id: championName) {
            retryCount = 0
            iconURL = await DataDragonService.shared.championIconURL(for: championName)
        }
    }

    private func retryAfterFailure() async {
        guard retryCount < Self.maxRetries else { return }
        retryCount += 1
        try? await Task.sleep(for: .milliseconds(400 * retryCount))
        guard !Task.isCancelled else { return }
        let url = await DataDragonService.shared.championIconURL(for: championName)
        // Swapping through nil forces AsyncImage to rebuild and restart the
        // load; reassigning the same URL value in place would not.
        iconURL = nil
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        iconURL = url
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }
}
