//
//  ClimbApp.swift
//  Climb
//
//  Created by Jialin Wu on 2026/9/2.
//

import SwiftUI
import SwiftData

@main
struct ClimbApp: App {
    init() {
        // `.fontDesign` doesn't reach UIKit-drawn text: navigation titles and
        // segmented pickers get the rounded face here instead.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.largeTitleTextAttributes = [.font: Self.rounded(.largeTitle, weight: .bold)]
        appearance.titleTextAttributes = [.font: Self.rounded(.headline, weight: .semibold)]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance

        let segments = UISegmentedControl.appearance()
        segments.setTitleTextAttributes([.font: Self.rounded(.subheadline, weight: .medium)], for: .normal)
        segments.setTitleTextAttributes([.font: Self.rounded(.subheadline, weight: .semibold)], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fontDesign(.rounded)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [
            LinkedAccount.self,
            Match.self,
            LeagueStats.self,
            TFTStats.self,
            CoachConversation.self,
            ChatMessage.self,
            MatchParticipantSummary.self,
            TeamStats.self,
            OpponentEncounter.self,
            GoldTimelinePoint.self,
            SavedPlayer.self
        ])
    }
}

private extension ClimbApp {
    static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let descriptor = base.fontDescriptor
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
            .withDesign(.rounded) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}
