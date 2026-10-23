import Foundation

struct RiotAccountResponse: Decodable {
    let puuid: String
}

struct RiotSummonerResponse: Decodable {
    let profileIconId: Int
    let summonerLevel: Int
    /// Milliseconds since epoch of the account's last activity, in practice a finished game.
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
            /// Voidgrubs: optional, older matches lack the field.
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

        // Optional: older matches and some modes omit them, and decoding mustn't fail for that.
        // Counts of things this player killed or destroyed, not damage.
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

        var items: [Int] {
            [item0, item1, item2, item3, item4, item5, item6]
        }

        struct Perks: Decodable {
            let styles: [Style]
            /// Optional: Riot omits it on modes without shards (Arena) and in older matches.
            let statPerks: StatPerks?

            struct StatPerks: Decodable {
                let offense: Int
                let flex: Int
                let defense: Int
            }

            struct Style: Decodable {
                /// "primaryStyle" or "subStyle"; matched by name, as array order isn't guaranteed.
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

            var primaryRuneIDs: [Int] { primary?.selections.map(\.perk) ?? [] }
            var secondaryRuneIDs: [Int] { secondary?.selections.map(\.perk) ?? [] }

            /// The stat shards in Riot's row order: offense, flex, defense.
            var statPerkIDs: [Int] {
                guard let statPerks else { return [] }
                return [statPerks.offense, statPerks.flex, statPerks.defense]
            }
        }
    }
}

/// Match-V5 timeline: the only record of who killed whom (the match response has only totals).
/// `participantId` is a 1-based index into `RiotMatchResponse.Info.participants`, not a puuid.
struct RiotMatchTimelineResponse: Decodable {
    let info: Info

    struct Info: Decodable {
        let frames: [Frame]
    }

    struct Frame: Decodable {
        let events: [Event]
        /// Keyed by participantId as a string ("1"..."10"); one snapshot per frame (~1 minute).
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
        /// On ELITE_MONSTER_KILL: DRAGON, BARON_NASHOR, RIFTHERALD, HORDE (Voidgrubs) or ATAKHAN.
        /// The only record of Herald and Voidgrub credit; the match summary has no field for them.
        let monsterType: String?
        let monsterSubType: String?
    }
}

/// TFT-Match-V1 uses snake_case keys; decode with `.convertFromSnakeCase` (as fetchTFTMatch does).
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
