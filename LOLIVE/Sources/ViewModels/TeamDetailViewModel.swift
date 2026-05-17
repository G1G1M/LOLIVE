//
//  TeamDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class TeamDetailViewModel {

    var players: [Player] = []
    var recentMatches: [Match] = []
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

        recentMatches = allMatches
            .filter {
                ($0.teamA.id == team.id || $0.teamA.code == team.code ||
                 $0.teamB.id == team.id || $0.teamB.code == team.code) &&
                $0.state == .completed
            }
            .sorted { $0.startTime > $1.startTime }
            .prefix(10)
            .map { $0 }
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
