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

    init(id: String, league: League, teamA: Team, teamB: Team,
         scoreA: Int, scoreB: Int, startTime: Date, state: MatchState,
         blockName: String? = nil) {
        self.id = id
        self.league = league
        self.teamA = teamA
        self.teamB = teamB
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.startTime = startTime
        self.state = state
        self.blockName = blockName
    }
}
