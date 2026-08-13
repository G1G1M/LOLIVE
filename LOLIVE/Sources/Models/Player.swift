//
//  Player.swift
//  LOLIVE
//

import Foundation

struct Player: Codable, Identifiable, Hashable {
    let id: String
    let summonerName: String
    let firstName: String?
    let lastName: String?
    let role: String
    let imageURL: String?
    let teamId: String
    let teamCode: String
}

struct PlayerSeasonStats: Codable {
    let games: Int
    let winRate: Double
    let avgKills: Double
    let avgDeaths: Double
    let avgAssists: Double
    let kdaRatio: Double
    let avgCSPerMin: Double
}

/// 선수 단위 시즌 집계 스탯 — Oracle's Elixir `/stats/players/byTournament` 응답을 앱에서
/// 쓰기 좋게 정리한 값. `PlayerSeasonStats`(Leaguepedia, 게임별 원본 행에서 직접 평균 계산)와
/// 별도 소스라 두 값이 100% 일치하진 않을 수 있음 — `games`는 팀 스탯(`TeamSeasonStats.games`)과
/// 같은 OE 시즌 집계 테이블에서 나와서 팀-선수 화면 간 경기 수 기준이 맞는 쪽은 이 값이다.
struct PlayerOEStats: Codable, Hashable {
    let games: Int              // GP — 선발 출전한 게임 수만 집계(교체 선수는 별도 행)
    let winRate: Double         // W%
    let kills: Int
    let deaths: Int
    let assists: Int
    let kda: Double
    let killParticipation: Double  // KP — 팀 킬 관여율
    let killShare: Double          // KS% — 팀 킬 중 본인 비중
    let deathShare: Double         // DTH% — 팀 데스 중 본인 비중
    let firstBloodRate: Double     // FB%
    let goldDiffAt10: Double?      // GD10
    let xpDiffAt10: Double?        // XPD10
    let csDiffAt10: Double?        // CSD10
    let csPerMin: Double           // CSPM
    let csShareAt15: Double        // CS%P15
    let damagePerMin: Double       // DPM
    let damageShare: Double        // DMG% — 팀 딜량 중 본인 비중
    let damageShareAt15: Double    // D%P15
    let totalDamagePerGame: Double // TDPG
    let earnedGoldPerMin: Double   // EGPM
    let goldShare: Double          // GOLD% — 팀 골드 중 본인 비중
    let steals: Int                // STL
    let wardsPerMinute: Double     // WPM
    let controlWardsPerMinute: Double // CWPM
    let wardsClearedPerMinute: Double // WCPM
}

struct ChampionPickEntry: Codable {
    let champion: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let won: Bool
    let date: Date?

    init(champion: String, kills: Int, deaths: Int, assists: Int, won: Bool, date: Date? = nil) {
        self.champion = champion
        self.kills = kills; self.deaths = deaths; self.assists = assists
        self.won = won; self.date = date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        champion = try c.decode(String.self, forKey: .champion)
        kills    = try c.decode(Int.self,    forKey: .kills)
        deaths   = try c.decode(Int.self,    forKey: .deaths)
        assists  = try c.decode(Int.self,    forKey: .assists)
        won      = try c.decode(Bool.self,   forKey: .won)
        date     = try? c.decode(Date.self,  forKey: .date)
    }
}
