//
//  Match.swift
//  LOLIVE
//

import Foundation

enum MatchState: String, Codable, Hashable {
    case unstarted
    case inProgress
    case completed
}

struct Match: Codable, Identifiable, Hashable {
    let id: String
    let league: League
    let teamA: Team
    let teamB: Team
    let scoreA: Int
    let scoreB: Int
    let startTime: Date
    let state: MatchState
    let blockName: String?  // "Week 1", "Playoffs", "Road to MSI" 등
    let games: [BackfilledGameDetail]?  // 과거 시즌 백필 경기에만 존재(oe.datalisk.io 게임별 상세)

    init(id: String, league: League, teamA: Team, teamB: Team,
         scoreA: Int, scoreB: Int, startTime: Date, state: MatchState,
         blockName: String? = nil, games: [BackfilledGameDetail]? = nil) {
        self.id = id
        self.league = league
        self.teamA = teamA
        self.teamB = teamB
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.startTime = startTime
        self.state = state
        self.blockName = blockName
        self.games = games
    }
}

/// 백필된 과거 시즌 경기(datalisk.io) 한 게임(세트)의 상세 정보 — 밴 데이터는 없음(원본에 없음).
struct BackfilledGameDetail: Codable, Hashable {
    let number: Int
    let gameId: String
    let patch: Double?
    let vod: String?
    let blueTeamId: String
    let redTeamId: String
    let winnerTeamId: String?
    let blueTeamStats: TeamGameStats
    let redTeamStats: TeamGameStats
    let bluePlayers: [PlayerStats]
    let redPlayers: [PlayerStats]
}
