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
    var showBracket: Bool = false
    var standings: [Standing] = []

    var standingGroups: [(name: String, standings: [Standing])] {
        var seen = Set<String>()
        let groupNames = standings.compactMap { $0.group }.filter { seen.insert($0).inserted }
        guard groupNames.count > 1 else { return [] }
        return groupNames.map { name in
            (name: name, standings: standings.filter { $0.group == name })
        }
    }
    var upcomingMatches: [Match] = []
    var completedMatches: [Match] = []
    var players: [Player] = []
    var isLoading = false
    var errorMessage: String? = nil

    // MARK: - Bracket

    struct BracketRound: Identifiable {
        let id: String
        let name: String
        let matches: [Match]
    }

    var isBracketAvailable: Bool {
        (upcomingMatches + completedMatches).contains {
            guard let b = $0.blockName?.lowercased() else { return false }
            return b.contains("final") || b.contains("semi") || b.contains("quarter") ||
                   b.contains("playoff") || b.contains("knockout") || b.contains("bracket") ||
                   b.contains("elimination")
        }
    }

    var bracketRounds: [BracketRound] {
        let all = completedMatches + upcomingMatches
        let byBlock = Dictionary(grouping: all.filter { $0.blockName != nil }) { $0.blockName! }
        return byBlock
            .filter { !isGroupStageBlock($0.key) }
            .map { name, matches in
                BracketRound(id: name, name: name, matches: matches.sorted { $0.startTime < $1.startTime })
            }.sorted { roundOrder($0.name) < roundOrder($1.name) }
    }

    private func isGroupStageBlock(_ name: String) -> Bool {
        let s = name.lowercased()
        return s.contains("swiss") || s.contains("group") ||
               s.contains("regular") || s.hasPrefix("week") ||
               s.contains("opening week") || s.contains("day ")
    }

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
            let r0 = RoleStyle.order($0.role), r1 = RoleStyle.order($1.role)
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

private func roundOrder(_ name: String) -> Int {
    let s = name.lowercased()
    if s.contains("play-in") || s.contains("playin")          { return 0 }
    if s.contains("round of 16")                               { return 1 }
    if s.contains("round of 8") || s.contains("quarter")       { return 2 }
    if s.contains("semi")                                      { return 3 }
    if s.contains("grand final")                               { return 5 }
    if s.contains("final")                                     { return 4 }
    if s.contains("playoff") || s.contains("knockout") ||
       s.contains("bracket stage") || s.contains("elimination") { return 1 }
    if s.contains("bracket")                                   { return 2 }
    return 6
}

