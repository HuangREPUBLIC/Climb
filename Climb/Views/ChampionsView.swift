import SwiftUI

/// The Champions tab (英雄): op.gg's tier list for one lane, each champion a
/// tap away from its build, runes, skill order and matchups.
struct ChampionsView: View {
    @AppStorage("championsPosition") private var position: OPGGPosition = .top
    @State private var meta: [OPGGPosition: [MetaChampion]] = [:]
    @State private var errorMessage: String?

    @ScaledMetric(relativeTo: .subheadline) private var portraitSize: CGFloat = 38
    @ScaledMetric(relativeTo: .caption) private var rateColumnWidth: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                Picker("Lane", selection: $position) {
                    ForEach(OPGGPosition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if let champions = meta[position] {
                    tierList(champions)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't load op.gg", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding()
            .readableContentWidth()
        }
        .background(Theme.background)
        .navigationTitle("Champions")
        .navigationDestination(for: ChampionRoute.self) { route in
            ChampionDetailView(champion: route.champion, position: route.position)
        }
        .refreshable { await load() }
        .task(id: position) {
            if meta[position] == nil { await load() }
        }
    }

    private func tierList(_ champions: [MetaChampion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Champion")
                Spacer()
                Text("Win").frame(width: rateColumnWidth, alignment: .trailing)
                Text("Pick").frame(width: rateColumnWidth, alignment: .trailing)
                Text("Ban").frame(width: rateColumnWidth, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.cardPadding)

            LazyVStack(spacing: 0) {
                ForEach(Array(champions.enumerated()), id: \.element.id) { index, champion in
                    if index > 0 { Divider() }
                    NavigationLink(value: ChampionRoute(champion: champion.champion, position: position)) {
                        row(champion)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .cardSurface()

            Text("Ranked data from op.gg, current patch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func row(_ champion: MetaChampion) -> some View {
        HStack(spacing: 10) {
            Text("\(champion.rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            ChampionIconView(championName: champion.champion, size: portraitSize)
            // Tier under the name, so the name gets the row's spare width.
            VStack(alignment: .leading, spacing: 2) {
                Text(champion.champion)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let tier = champion.tier { TierBadge(tier: tier) }
            }
            Spacer(minLength: 4)
            percent(champion.winRate)
                .foregroundStyle(champion.winRate >= 0.5 ? Theme.win : .primary)
            percent(champion.pickRate).foregroundStyle(.secondary)
            percent(champion.banRate).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Whole percents: op.gg rounds its rates to two decimals, so "51.0%"
    /// would claim a precision the data doesn't have.
    private func percent(_ value: Double) -> some View {
        Text(value.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption.monospacedDigit())
            .frame(width: rateColumnWidth, alignment: .trailing)
    }

    private func load() async {
        errorMessage = nil
        do {
            meta[position] = try await OPGGClient.shared.laneMeta(position)
        } catch is CancellationError {
            // Switched lanes mid-load; the new lane's task takes over.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ChampionRoute: Hashable {
    let champion: String
    let position: OPGGPosition
}

/// op.gg's tier as a coloured pill: 0 is its "OP" grade, then 1 to 5.
struct TierBadge: View {
    let tier: Int

    private var tint: Color {
        switch tier {
        case 0: return Theme.poor
        case 1: return Theme.orange
        case 2: return .blue
        case 3: return Theme.good
        default: return .secondary
        }
    }

    var body: some View {
        Text(tier == 0 ? "OP" : "T\(tier)")
            .scaledFont(9, weight: .black)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel(tier == 0 ? "OP tier" : "Tier \(tier)")
    }
}
