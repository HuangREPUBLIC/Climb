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
    var body: some Scene {
        WindowGroup {
            ContentView()
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
