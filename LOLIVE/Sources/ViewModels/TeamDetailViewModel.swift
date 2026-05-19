//
//  TeamDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

struct H2HRecord: Identifiable {
    var id: String { opponent.id.isEmpty ? opponent.code : opponent.id }
    let opponent: Team
    var wins: Int
    var losses: Int
    var winRate: Double { wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses) }
}

@MainActor
@Observable
final class TeamDetailViewModel {

    var players: [Player] = []
    var recentMatches: [Match] = []
    var h2hRecords: [H2HRecord] = []
    var isLoading = false

    private let team: Team
    private let league: League
    private let service: RiotEsportsServiceProtocol

    init(team: Team, league: League,
         service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.team = team
        self.league = league
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let rosterTask = service.fetchTeamRoster(teamId: team.id)
        async let scheduleTask = service.fetchSchedule(league: league)

        let roster = (try? await rosterTask) ?? []
        let allMatches = (try? await scheduleTask) ?? []

        players = roster.sorted { roleOrder($0.role) < roleOrder($1.role) }

        let completed = allMatches.filter {
            ($0.teamA.id == team.id || $0.teamA.code == team.code ||
             $0.teamB.id == team.id || $0.teamB.code == team.code) &&
            $0.state == .completed
        }.sorted { $0.startTime > $1.startTime }

        recentMatches = Array(completed.prefix(10))
        h2hRecords = buildH2H(from: completed)
    }

    private func buildH2H(from matches: [Match]) -> [H2HRecord] {
        var dict: [String: H2HRecord] = [:]
        for match in matches {
            let isTeamA = match.teamA.id == team.id || match.teamA.code == team.code
            let opponent = isTeamA ? match.teamB : match.teamA
            let myScore  = isTeamA ? match.scoreA : match.scoreB
            let oppScore = isTeamA ? match.scoreB : match.scoreA
            let key = opponent.id.isEmpty ? opponent.code : opponent.id
            var record = dict[key] ?? H2HRecord(opponent: opponent, wins: 0, losses: 0)
            if myScore > oppScore { record.wins += 1 } else { record.losses += 1 }
            dict[key] = record
        }
        return dict.values.sorted { $0.opponent.name < $1.opponent.name }
    }
}

private func roleOrder(_ role: String) -> Int {
    switch role.lowercased() {
    case "top":              return 0
    case "jungle":           return 1
    case "mid":              return 2
    case "bottom", "bot":    return 3
    case "support":          return 4
    default:                 return 5
    }
}
