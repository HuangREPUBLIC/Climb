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
    @State private var selectedTab: Tab = .profile
    @State private var matchPath = NavigationPath()

    @ObservedObject private var router = NotificationRouter.shared

    private enum Tab {
        case profile, matches, stats
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(Tab.profile)

            NavigationStack(path: $matchPath) {
                MatchListView()
            }
            .tabItem {
                Label("Matches", systemImage: "list.bullet")
            }
            .tag(Tab.matches)

            NavigationStack {
                StatsView()
            }
            .tabItem {
                Label("Stats", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(Tab.stats)
        }
        .task {
            NotificationRouter.shared.start()
            MockData.seedIfNeeded(context: modelContext)
            NotificationService.requestAuthorizationIfNeeded()
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

#Preview {
    ContentView()
        .modelContainer(for: Match.self, inMemory: true)
}
