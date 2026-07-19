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
    var isLoadingLeagues = true
    var isLoadingStandings = false
    var loadFailed = false

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
        let hadCache = preloadFromCache()
        isLoadingLeagues = !hadCache
        loadFailed = false
        defer { isLoadingLeagues = false }

        let fetchResult = try? await service.fetchLeagues()
        if let fetched = fetchResult {
            leagues = fetched
                .filter { !excludedRegions.contains($0.region) }
                .filter { league in
                    let name = league.name.lowercased()
                    return !secondaryKeywords.contains(where: { name.contains($0) })
                }
                .sorted { regionOrder($0.region) < regionOrder($1.region) }
        } else if !hadCache {
            loadFailed = true
            return
        }

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
        if let cached = standingsCache[league.id] {
            standings = cached
            return
        }

        if let diskCached = preloadStandingsFromCache(for: league) {
            standings = diskCached
            standingsCache[league.id] = diskCached
        } else {
            isLoadingStandings = true
        }
        defer { isLoadingStandings = false }

        guard let tournaments = try? await service.fetchTournaments(leagueId: league.id),
              let tournament = activeTournament(from: tournaments) else {
            standings = []
            return
        }

        async let standingsFetch = service.fetchStandings(tournamentId: tournament.id)
        async let scheduleFetch = service.fetchSchedule(league: league)

        let fetched = (try? await standingsFetch) ?? []
        let schedule = (try? await scheduleFetch) ?? []

        let sorted = applyGD(fetched, schedule: schedule)
        standingsCache[league.id] = sorted
        standings = sorted
    }

    private func preloadFromCache() -> Bool {
        guard let fetched: [League] = AppDiskCache.get(key: "leagues", maxAge: 24 * 3600) else { return false }
        let filtered = fetched
            .filter { !excludedRegions.contains($0.region) }
            .filter { league in
                let name = league.name.lowercased()
                return !secondaryKeywords.contains(where: { name.contains($0) })
            }
            .sorted { regionOrder($0.region) < regionOrder($1.region) }
        guard !filtered.isEmpty else { return false }
        leagues = filtered
        let first = filtered[0]
        selectedLeague = first
        if let cached = preloadStandingsFromCache(for: first) {
            standings = cached
            standingsCache[first.id] = cached
        }
        return true
    }

    private func preloadStandingsFromCache(for league: League) -> [Standing]? {
        guard let tournaments: [Tournament] = AppDiskCache.get(key: "tournaments_\(league.id)", maxAge: 24 * 3600),
              let tournament = activeTournament(from: tournaments),
              let fetched: [Standing] = AppDiskCache.get(key: "standings_\(tournament.id)", maxAge: 3600)
        else { return nil }
        let schedule: [Match] = AppDiskCache.get(key: "schedule_\(league.id)", maxAge: 15 * 60) ?? []
        return applyGD(fetched, schedule: schedule)
    }

    private func applyGD(_ standings: [Standing], schedule: [Match]) -> [Standing] {
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
        return standings.map { s in
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
