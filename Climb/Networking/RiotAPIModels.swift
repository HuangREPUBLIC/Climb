import Foundation

struct RiotAccountResponse: Decodable {
    let puuid: String
    let gameName: String?
    let tagLine: String?
}

struct RiotSummonerResponse: Decodable {
    let profileIconId: Int
    let summonerLevel: Int
    /// Milliseconds since epoch, updated when the account last did something —
    /// in practice, finished a game. Free to read here because this endpoint is
    /// already called on every sync for the icon and level.
    let revisionDate: Double?
}

struct RiotLeagueEntry: Decodable {
    let queueType: String
    let tier: String
    let rank: String
    let leaguePoints: Int
    let wins: Int
    let losses: Int
}

struct RiotMatchResponse: Decodable {
    let metadata: Metadata
    let info: Info

    struct Metadata: Decodable {
        let matchId: String
    }

    struct Info: Decodable {
        let gameCreation: Int64
        let gameDuration: Int
        let queueId: Int
        let participants: [Participant]
        let teams: [Team]
    }

    struct Team: Decodable {
        let teamId: Int
        let win: Bool
        let objectives: Objectives

        struct Objectives: Decodable {
            let baron: Objective
            let dragon: Objective
            let tower: Objective
            let inhibitor: Objective
            let riftHerald: Objective
            /// Voidgrubs, added in 2024 — optional because matches played before
            /// they existed simply don't carry the field.
            let horde: Objective?

            struct Objective: Decodable {
                let kills: Int
            }
        }
    }

    struct Participant: Decodable {
        let puuid: String
        let riotIdGameName: String
        let riotIdTagline: String
        let championName: String
        let teamId: Int
        let teamPosition: String
        let kills: Int
        let deaths: Int
        let assists: Int
        let win: Bool
        let totalMinionsKilled: Int
        let neutralMinionsKilled: Int
        let item0: Int
        let item1: Int
        let item2: Int
        let item3: Int
        let item4: Int
        let item5: Int
        let item6: Int
        let summoner1Id: Int
        let summoner2Id: Int
        let goldEarned: Int
        let totalDamageDealtToChampions: Int
        let totalDamageTaken: Int
        let totalHeal: Int
        let visionScore: Int
        let wardsPlaced: Int
        let doubleKills: Int
        let tripleKills: Int
        let quadraKills: Int
        let pentaKills: Int
        let perks: Perks

        // Optional because older matches (and some game modes) omit them —
        // decoding must not fail just because a 2021 game lacks a field.
        // These are *counts of things killed/destroyed by this player*, not
        // damage numbers. Rift Herald and Voidgrubs have no participant-level
        // field at all, so those come from timeline ELITE_MONSTER_KILL events.
        let turretKills: Int?
        let inhibitorKills: Int?
        let dragonKills: Int?
        let baronKills: Int?
        let objectivesStolen: Int?
        let firstBloodKill: Bool?
        let largestKillingSpree: Int?
        let wardsKilled: Int?
        let largestMultiKill: Int?
        let champLevel: Int?
        // Arena / Brawl / ARAM: Mayhem augment picks. Zero when unused, and
        // absent entirely on older matches.
        let playerAugment1: Int?
        let playerAugment2: Int?
        let playerAugment3: Int?
        let playerAugment4: Int?
        let playerAugment5: Int?
        let playerAugment6: Int?

        var augmentIDs: [Int] {
            [playerAugment1, playerAugment2, playerAugment3,
             playerAugment4, playerAugment5, playerAugment6]
                .compactMap { $0 }
                .filter { $0 != 0 }
        }

        var items: [Int] {
            [item0, item1, item2, item3, item4, item5, item6]
        }

        struct Perks: Decodable {
            let styles: [Style]
            /// Optional because Riot omits it on modes that have no shards
            /// (Arena, and older matches), not because it is ever partial.
            let statPerks: StatPerks?

            struct StatPerks: Decodable {
                let offense: Int
                let flex: Int
                let defense: Int
            }

            struct Style: Decodable {
                /// "primaryStyle" or "subStyle" — matched by name rather than
                /// array position, which Riot does not guarantee.
                let description: String?
                let style: Int
                let selections: [Selection]

                struct Selection: Decodable {
                    let perk: Int
                }
            }

            private var primary: Style? {
                styles.first { $0.description == "primaryStyle" } ?? styles.first
            }
            private var secondary: Style? {
                styles.first { $0.description == "subStyle" } ?? (styles.count > 1 ? styles[1] : nil)
            }

            var keystoneID: Int { primary?.selections.first?.perk ?? 0 }
            var primaryStyleID: Int { primary?.style ?? 0 }
            var subStyleID: Int { secondary?.style ?? 0 }

            /// All four primary-tree picks, keystone first.
            var primaryRuneIDs: [Int] { primary?.selections.map(\.perk) ?? [] }
            /// Both secondary-tree picks.
            var secondaryRuneIDs: [Int] { secondary?.selections.map(\.perk) ?? [] }

            /// The three stat shards in Riot's own row order — offence, flex,
            /// defence — which is the order the client shows them in.
            var statPerkIDs: [Int] {
                guard let statPerks else { return [] }
                return [statPerks.offense, statPerks.flex, statPerks.defense]
            }
        }
    }
}

/// Match-V5 timeline — the only place Riot records *who* killed *whom*.
/// The base match response only has aggregate totals, so any "you vs this
/// specific opponent" kill/death/assist breakdown has to come from here.
/// `participantId` (1-10) is NOT the same as `puuid` — it's the opponent's
/// 1-based index into `RiotMatchResponse.Info.participants`.
struct RiotMatchTimelineResponse: Decodable {
    let info: Info

    struct Info: Decodable {
        let frames: [Frame]
    }

    struct Frame: Decodable {
        let events: [Event]
        /// Keyed by participantId as a string ("1"..."10"); one snapshot per
        /// frame (~1 minute), which is what makes a gold/XP curve possible.
        let participantFrames: [String: ParticipantFrame]?
        /// Milliseconds since game start.
        let timestamp: Int?
    }

    struct ParticipantFrame: Decodable {
        let participantId: Int
        let totalGold: Int
        let xp: Int
    }

    struct Event: Decodable {
        let type: String
        let killerId: Int?
        let victimId: Int?
        let assistingParticipantIds: [Int]?
        /// On ELITE_MONSTER_KILL: DRAGON / BARON_NASHOR / RIFTHERALD /
        /// HORDE (Voidgrubs) / ATAKHAN. The only place Herald and Voidgrub
        /// credit is recorded — the match summary has no field for them.
        let monsterType: String?
        let monsterSubType: String?
    }
}

/// TFT-Match-V1 responses use snake_case keys; decode with a
/// `.convertFromSnakeCase` JSONDecoder (RiotAPIClient.fetchTFTMatch does this).
struct RiotTFTMatchResponse: Decodable {
    let metadata: Metadata
    let info: Info

    struct Metadata: Decodable {
        let matchId: String
    }

    struct Info: Decodable {
        let gameDatetime: Int64
        let gameLength: Double
        let queueId: Int
        let participants: [Participant]
    }

    struct Participant: Decodable {
        let puuid: String
        let placement: Int
        let level: Int
        let traits: [Trait]
        let units: [Unit]

        struct Trait: Decodable {
            let name: String
            let tierCurrent: Int
        }

        struct Unit: Decodable {
            let characterId: String
        }
    }
}
