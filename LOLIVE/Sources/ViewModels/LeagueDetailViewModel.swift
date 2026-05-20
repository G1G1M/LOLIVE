//
//  LeagueDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class LeagueDetailViewModel {

    // MARK: - Tab

    enum Tab: CaseIterable {
        case standings, schedule, teams, players

        var title: String {
            switch self {
            case .standings: return "순위"
            case .schedule:  return "일정"
            case .teams:     return "팀"
            case .players:   return "선수"
            }
        }
    }

    // MARK: - Properties

    var selectedTab: Tab = .standings
    var standings: [Standing] = []
    var upcomingMatches: [Match] = []
    var completedMatches: [Match] = []
    var players: [Player] = []
    var isLoading = false
    var errorMessage: String? = nil

    // MARK: - Private

    private let league: League
    private let service: RiotEsportsServiceProtocol

    // MARK: - Init

    init(league: League, service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.league = league
        self.service = service
    }

    // MARK: - Public

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // 일정 + 토너먼트 병렬 조회
        async let scheduleTask = service.fetchSchedule(league: league)
        async let tournamentsTask = service.fetchTournaments(leagueId: league.id)
        let allMatches = (try? await scheduleTask) ?? []
        let tournaments = (try? await tournamentsTask) ?? []

        let now = Date()
        upcomingMatches = allMatches
            .filter { $0.startTime >= now && $0.state == .unstarted }
            .sorted { $0.startTime < $1.startTime }
        completedMatches = allMatches
            .filter { $0.state == .completed }
            .sorted { $0.startTime > $1.startTime }

        // 현재 토너먼트로 순위 + 선수 조회
        guard let tournament = activeTournament(from: tournaments) else { return }

        var fetchedStandings = (try? await service.fetchStandings(tournamentId: tournament.id)) ?? []

        // 세트 득실차 계산 (팀 코드 기준 매칭 — StandingsViewModel과 동일 로직)
        let completed = allMatches.filter { $0.state == .completed }
        var gameWinsMap: [String: Int] = [:]
        var gameLossesMap: [String: Int] = [:]
        for match in completed {
            let aCode = match.teamA.code.uppercased()
            let bCode = match.teamB.code.uppercased()
            gameWinsMap[aCode, default: 0] += match.scoreA
            gameLossesMap[aCode, default: 0] += match.scoreB
            gameWinsMap[bCode, default: 0] += match.scoreB
            gameLossesMap[bCode, default: 0] += match.scoreA
        }
        fetchedStandings = fetchedStandings.map { s in
            var s = s
            let code = s.team.code.uppercased()
            s.gameWins = gameWinsMap[code] ?? 0
            s.gameLosses = gameLossesMap[code] ?? 0
            return s
        }.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.gameDiff != $1.gameDiff { return $0.gameDiff > $1.gameDiff }
            return $0.team.name < $1.team.name
        }
        standings = fetchedStandings

        let teamIds = fetchedStandings.map { $0.team.id }
        let svc = service

        // Leaguepedia에서 이 리그의 공식 선수 목록 조회 (Riot API 로스터와 병렬)
        async let leaguepediaTask = LeaguepediaService.shared.playerNames(league: league)

        let rawPlayers = await withTaskGroup(of: [Player].self) { group in
            for teamId in teamIds {
                group.addTask { (try? await svc.fetchTeamRoster(teamId: teamId)) ?? [] }
            }
            var result: [Player] = []
            for await roster in group { result.append(contentsOf: roster) }
            return result
        }

        let validNames = await leaguepediaTask

        let filteredPlayers: [Player]
        if let validNames {
            // Leaguepedia 공식 명단 기준 필터
            filteredPlayers = rawPlayers.filter { validNames.contains($0.summonerName.lowercased()) }
        } else {
            // Fallback: 팀·포지션별 1명 (Riot API 조직 전체 반환 대응)
            var seenTeamRole = Set<String>()
            filteredPlayers = rawPlayers.filter { player in
                let role = player.role.lowercased()
                guard !role.isEmpty else { return false }
                return seenTeamRole.insert("\(player.teamId)_\(role)").inserted
            }
        }

        players = filteredPlayers.sorted {
            let r0 = roleOrder($0.role), r1 = roleOrder($1.role)
            return r0 != r1 ? r0 < r1 : $0.summonerName < $1.summonerName
        }
    }

    // MARK: - Private

    private func activeTournament(from tournaments: [Tournament]) -> Tournament? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        // 현재 진행 중인 토너먼트 우선, 없으면 가장 최근
        let active = tournaments.first {
            guard let s = fmt.date(from: $0.startDate),
                  let e = fmt.date(from: $0.endDate) else { return false }
            return now >= s && now <= e
        }
        return active ?? tournaments.last
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
