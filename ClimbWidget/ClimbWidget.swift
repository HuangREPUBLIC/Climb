import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now, snapshot: nil, imageData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        Task {
            let snapshot = WidgetSnapshotReader.read()
            let imageData = await Self.fetchImageData(for: snapshot)
            completion(SimpleEntry(date: .now, snapshot: snapshot, imageData: imageData))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task {
            let snapshot = WidgetSnapshotReader.read()
            let imageData = await Self.fetchImageData(for: snapshot)
            let entry = SimpleEntry(date: .now, snapshot: snapshot, imageData: imageData)
            completion(Timeline(entries: [entry], policy: .never))
        }
    }

    /// Pre-fetches the splash art so it's already in hand when WidgetKit
    /// snapshots the view — AsyncImage's live fetch is too slow for that
    /// snapshot moment and just renders blank forever until the next reload.
    private static func fetchImageData(for snapshot: LatestMatchSnapshot?) async -> Data? {
        guard let snapshot, let url = WidgetChampionArt.splashURL(for: snapshot.champion) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let snapshot: LatestMatchSnapshot?
    let imageData: Data?
}

struct ClimbWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                background
            }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 3) {
                Spacer(minLength: 0)
                HStack(alignment: .top) {
                    Text(snapshot.champion)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(snapshot.win ? "WIN" : "LOSS")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(snapshot.win ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                        .foregroundStyle(snapshot.win ? .green : .red)
                        .clipShape(Capsule())
                }
                Text("\(snapshot.kills)/\(snapshot.deaths)/\(snapshot.assists)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                if family == .systemMedium {
                    Text(snapshot.queueType)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Text(snapshot.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(12)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "gamecontroller")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Open Climb and link your Riot account")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    @ViewBuilder
    private var background: some View {
        if let data = entry.imageData, let uiImage = UIImage(data: data) {
            ZStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                LinearGradient(
                    colors: [.black.opacity(0.1), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            Color(.secondarySystemBackground)
        }
    }
}

struct ClimbWidget: Widget {
    let kind: String = "ClimbWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ClimbWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Latest Match")
        .description("Shows your most recent League of Legends match.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ClimbWidget()
} timeline: {
    SimpleEntry(
        date: .now,
        snapshot: LatestMatchSnapshot(champion: "Ahri", win: true, kills: 8, deaths: 2, assists: 10, queueType: "Ranked Solo", timestamp: .now),
        imageData: nil
    )
    SimpleEntry(date: .now, snapshot: nil, imageData: nil)
}
