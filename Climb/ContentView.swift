import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [LinkedAccount]
    /// See OnboardingView.isLinking.
    @State private var isLinking = false

    /// Owned here rather than in each screen: a tapped notification switches tabs and pushes a
    /// destination from outside them.
    @State private var selectedTab: Tab = .matches
    @State private var matchPath = NavigationPath()
    /// Hides the bar for the keyboard: in the safe area it would ride up onto the chat input.
    @State private var keyboardShown = false
    /// Set by a screen that wants the whole height; see `hidesTabBar()`.
    @State private var screenHidesBar = false
    /// Bar height, applied as a margin: its safe-area inset doesn't reach the tabs' scroll views.
    @State private var barHeight: CGFloat = 0

    @ObservedObject private var router = NotificationRouter.shared
    @ObservedObject private var keyPrompt = APIKeyPrompt.shared

    enum Tab: String, CaseIterable {
        case matches = "Matches", champions = "Champions", stats = "Stats", search = "Search"

        var icon: String {
            switch self {
            case .matches: "list.bullet.rectangle.portrait.fill"
            case .champions: "star.circle.fill"
            case .stats: "chart.line.uptrend.xyaxis"
            case .search: "magnifyingglass"
            }
        }
    }

    var body: some View {
        Group {
            if accounts.isEmpty || isLinking {
                OnboardingView(isLinking: $isLinking)
            } else {
                tabs
            }
        }
        .sheet(isPresented: $keyPrompt.isPresented) {
            NavigationStack {
                APIKeysView(reason: "Riot rejected the API key. Personal keys expire after 24 hours — paste today's to keep syncing.")
            }
        }
        .task {
            APIKeys.seedFromSecretsIfNeeded()
            NotificationRouter.shared.start()
            #if DEBUG
            PerformanceScore.selfCheck()
            MatchRowView.selfCheck()
            OPGGNotation.selfCheck()
            CoachReply.selfCheck()
            MatchImportService.selfCheck()
            assert(LinkedAccount.identity(gameName: "Hideonbush", tagLine: "kr1") == LinkedAccount.identity(gameName: "Hide on bush", tagLine: "KR1"), "Riot ID ignores case and spaces")
            #endif
            // Notification permission is asked when the first reminder is scheduled, not at launch.
            // A notification cold launch sets the id before this view exists: consume it here too.
            consumePendingMatch()
            await MatchImportService.refreshIfNeeded(context: modelContext)
        }
        .onChange(of: router.pendingMatchID) {
            consumePendingMatch()
        }
        // Logging out leaves Settings on the path; the next login would open there.
        .onChange(of: accounts.isEmpty) {
            if accounts.isEmpty { matchPath = NavigationPath() }
        }
    }

    /// TabView still owns each tab's lifetime and navigation state; only its bar is replaced.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $matchPath) {
                ProfileView(path: $matchPath)
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(Tab.matches)

            NavigationStack {
                ChampionsView()
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(Tab.champions)

            NavigationStack {
                StatsView()
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(Tab.stats)

            NavigationStack {
                SearchView()
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(Tab.search)
        }
        .contentMargins(.bottom, keyboardShown || screenHidesBar ? 0 : barHeight, for: .scrollContent)
        // Hard edge: the soft one let content show through the bar and under the clock.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardShown && !screenHidesBar {
                ClimbTabBar(selection: $selectedTab)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
            }
        }
        .onPreferenceChange(TabBarHiddenKey.self) { screenHidesBar = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
    }

    /// Opens the reminder's match on the Matches tab; a missing match just clears the request.
    private func consumePendingMatch() {
        guard let matchID = router.pendingMatchID else { return }
        router.pendingMatchID = nil

        var descriptor = FetchDescriptor<Match>(predicate: #Predicate { $0.id == matchID })
        descriptor.fetchLimit = 1
        guard let match = try? modelContext.fetch(descriptor).first else { return }

        selectedTab = .matches
        matchPath = NavigationPath()
        matchPath.append(match)
    }
}

/// The custom bar's `.toolbar(.hidden, for: .tabBar)`, which only reaches the system bar.
struct TabBarHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func hidesTabBar() -> some View { preference(key: TabBarHiddenKey.self, value: true) }
}

private struct ClimbTabBar: View {
    @Binding var selection: ContentView.Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = tab }
                } label: {
                    // Labelled, since the Champions star alone meant nothing to non-players.
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.body.weight(.semibold))
                        Text(tab.rawValue)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.accentGradient)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .background {
            Capsule().fill(.regularMaterial)
            Capsule().fill(Theme.surface.opacity(0.85))
        }
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Match.self, LinkedAccount.self, SavedPlayer.self], inMemory: true)
}
