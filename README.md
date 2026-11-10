# Climb

An iOS app for League of Legends and TFT players to review their ranked games: match history, lobby-relative performance scores, stat trends, and an AI coach that explains what went right and wrong in each game.

Built with SwiftUI and SwiftData for iOS 26.

## Features

- **Match history**: Riot ID sign-in, the 20 most recent games synced first and more loaded on scroll, grouped by day with win/loss totals. Long-press a card for a quick preview.
- **Match detail**: a full scoreboard for both teams, team comparison (gold lead over time), lane matchup, and your own performance breakdown.
- **Performance rating**: a 0–10 score for each game, measured against the other nine players in that lobby and adjusted for role.
- **Stats dashboard**: win rate, KDA, CS, damage and vision trends with sparklines, plus best champions and multikill highlights.
- **AI coach** (Gemini): a review for each match and a diagnosis of recent trends. The charts come from real match data and the model only writes the explanation. A chat lets you ask follow-up questions.
- **Champions tab**: tier lists and builds from op.gg.
- **Search and Following**: look up any player's profile and follow them.
- **Saved games, tags and notes** on matches.
- **Home-screen widget** (WidgetKit) showing your recent form, shared through an App Group.

## Tech

| Area | Used |
| --- | --- |
| UI | SwiftUI, Swift Charts, iOS 26 Liquid Glass |
| Persistence | SwiftData |
| Networking | `URLSession` + async/await, Riot API (account-v1, match-v5, league-v4), Data Dragon, op.gg MCP |
| AI | Gemini via its OpenAI-compatible endpoint, with model fallback on 429/503 |
| Security | API keys stored in the Keychain and entered in the app; never committed |
| Extensions | WidgetKit, local notifications |

## Running it

1. Open `Climb.xcodeproj` in Xcode 26 or later.
2. Get a personal Riot API key from [developer.riotgames.com](https://developer.riotgames.com/) (it expires every 24 hours) and an optional Gemini key from [aistudio.google.com](https://aistudio.google.com/apikey).
3. Run the app in the Simulator and paste the keys under **Settings → API Keys**. To seed them instead, see `Climb/Secrets.example.txt`.

## Legal

Climb isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games and all associated properties are trademarks or registered trademarks of Riot Games, Inc.
