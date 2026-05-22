//
//  StandingsViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class StandingsViewModel {

    // MARK: - Properties

    var leagues: [League] = []
    var standings: [Standing] = []
    var selectedLeague: League? = nil
    var isLoadingLeagues = false
    var isLoadingStandings = false

    // 그룹이 2개 이상일 때 사용. 단일 그룹이면 빈 배열 반환
    var standingGroups: [(name: String, standings: [Standing])] {
        var seen = Set<String>()
        let groupNames = standings.compactMap { $0.group }.filter { seen.insert($0).inserted }
        guard groupNames.count > 1 else { return [] }
        return groupNames.map { name in
            (name: name, standings: standings.filter { $0.group == name })
        }
    }

    // MARK: - Private

    private let service: RiotEsportsServiceProtocol
    private var standingsCache: [String: [Standing]] = [:]

    private let excludedRegions: Set<String> = ["국제 대회"]
    private let secondaryKeywords = ["챌린저스", "challengers", "academy", "circuito desafiante"]

    // MARK: - Init

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
    }

    // MARK: - Public

    func loadLeagues() async {
        isLoadingLeagues = true
        defer { isLoadingLeagues = false }

        let fetched = (try? await service.fetchLeagues()) ?? []
        leagues = fetched
            .filter { !excludedRegions.contains($0.region) }
            .filter { league in
                let name = league.name.lowercased()
                return !secondaryKeywords.contains(where: { name.contains($0) })
            }
            .sorted { regionOrder($0.region) < regionOrder($1.region) }

        // 기본 선택: 첫 번째 리그
        if let first = leagues.first {
            selectedLeague = first
            await loadStandings(for: first)
        }
    }

    func selectLeague(_ league: League) async {
        guard selectedLeague?.id != league.id else { return }
        selectedLeague = league
        await loadStandings(for: league)
    }

    func refreshStandings() async {
        guard let league = selectedLeague else { return }
        standingsCache.removeValue(forKey: league.id)
        AppDiskCache.clear(key: "standings_\(league.id)")
        await loadStandings(for: league)
    }

    // MARK: - Private

    private func loadStandings(for league: League) async {
        // 캐시 확인
        if let cached = standingsCache[league.id] {
            standings = cached
            return
        }

        isLoadingStandings = true
        defer { isLoadingStandings = false }

        guard let tournaments = try? await service.fetchTournaments(leagueId: league.id),
              let tournament = activeTournament(from: tournaments) else {
            standings = []
            return
        }

        async let standingsFetch = service.fetchStandings(tournamentId: tournament.id)
        async let scheduleFetch = service.fetchSchedule(league: league)

        var fetched = (try? await standingsFetch) ?? []
        let schedule = (try? await scheduleFetch) ?? []

        // 완료된 경기의 세트 득실차 계산 (팀 코드 기준 매칭 — ID 불일치 방지)
        let completed = schedule.filter { $0.state == .completed }
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

        fetched = fetched.map { standing in
            var s = standing
            let code = standing.team.code.uppercased()
            s.gameWins = gameWinsMap[code] ?? 0
            s.gameLosses = gameLossesMap[code] ?? 0
            return s
        }.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.gameDiff != $1.gameDiff { return $0.gameDiff > $1.gameDiff }
            return $0.team.name < $1.team.name
        }

        standingsCache[league.id] = fetched
        standings = fetched
    }

    private func activeTournament(from tournaments: [Tournament]) -> Tournament? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let active = tournaments.first {
            guard let s = fmt.date(from: $0.startDate),
                  let e = fmt.date(from: $0.endDate) else { return false }
            return now >= s && now <= e
        }
        return active ?? tournaments.last
    }

    private func regionOrder(_ region: String) -> Int {
        switch region {
        case "한국":                     return 0
        case "중국":                     return 1
        case "EMEA":                     return 2
        case "북미":                     return 3
        case "퍼시픽":                   return 4
        case "아메리카스":               return 5
        case "일본":                     return 6
        case "베트남":                   return 7
        case "브라질":                   return 8
        case "홍콩, 마카오, 대만":       return 9
        case "라틴 아메리카":            return 10
        case "라틴 아메리카 북부":       return 11
        case "라틴 아메리카 남부":       return 12
        case "오세아니아":               return 13
        case "독립 국가 연합 (CIS)":     return 14
        default:                         return 15
        }
    }
}
