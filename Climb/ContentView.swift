//
//  ContentView.swift
//  Climb
//
//  Created by Jialin Wu on 2026/9/2.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    /// The tab and the Matches stack are owned here rather than inside each
    /// screen, because a tapped notification has to be able to switch tabs and
    /// push a destination from outside any of them.
    @State private var selectedTab: Tab = .matches
    @State private var matchPath = NavigationPath()
    /// The custom bar sits in the safe area, so it would ride up on the
    /// keyboard — onto the coach chat's input. The system bar stayed behind
    /// the keyboard; this keeps that.
    @State private var keyboardShown = false
    /// Set by a screen that wants the whole height; see `hidesTabBar()`.
    @State private var screenHidesBar = false

    @ObservedObject private var router = NotificationRouter.shared
    @ObservedObject private var keyPrompt = APIKeyPrompt.shared

    enum Tab: CaseIterable {
        case matches, champions, stats, search

        var title: String {
            switch self {
            case .matches: "Matches"
            case .champions: "Champions"
            case .stats: "Stats"
            case .search: "Search"
            }
        }

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
        // TabView still owns each tab's lifetime and navigation state; only
        // its bar is swapped for ClimbTabBar.
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardShown && !screenHidesBar { ClimbTabBar(selection: $selectedTab) }
        }
        .onPreferenceChange(TabBarHiddenKey.self) { screenHidesBar = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
        .sheet(isPresented: $keyPrompt.riotKeyRejected) {
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
            #endif
            // Notification permission is requested in context — right before the
            // first reflection reminder is actually scheduled, in
            // NotificationService.scheduleReflectionReminder — rather than here
            // on cold launch, before the player has linked an account or has any
            // reason to know what the permission is for.
            // A cold launch from a notification records the id before this view
            // exists, so the pending value is consumed here as well as on change.
            consumePendingMatch()
            // Backfills newly-tracked fields on existing matches without the
            // user having to re-enter their Riot ID.
            await MatchImportService.refreshIfNeeded(context: modelContext)
        }
        .onChange(of: router.pendingMatchID) {
            consumePendingMatch()
        }
    }

    /// Opens the match a reflection reminder was about: Matches tab, then that
    /// match's detail screen. A match that no longer exists (deleted, or wiped
    /// by a re-import) just clears the request rather than leaving it pending.
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

/// The custom bar's version of `.toolbar(.hidden, for: .tabBar)`, which only
/// reaches the system bar.
struct TabBarHiddenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func hidesTabBar() -> some View { preference(key: TabBarHiddenKey.self, value: true) }
}

/// The floating bottom bar: a white capsule where the selected tab is a gold
/// pill with its name, and the others are icons only.
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
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.body.weight(.semibold))
                        if selected {
                            Text(tab.title)
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: selected ? nil : .infinity, minHeight: 48)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.accent)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
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
