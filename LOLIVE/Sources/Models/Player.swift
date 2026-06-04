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
