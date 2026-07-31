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
    private var tournamentIdByLeague: [String: String] = [:]

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
        // standings는 tournamentId 기준으로 캐싱되므로(league.id가 아님) 마지막으로 알고 있던
        // tournamentId로 지워야 실제로 지워진다 — 예전엔 league.id로 지워서 아무 캐시도 안 지워지던 버그였음
        if let tournamentId = tournamentIdByLeague[league.id] {
            AppDiskCache.clear(.standings(tournamentId: tournamentId))
        }
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
        tournamentIdByLeague[league.id] = tournament.id

        async let standingsFetch = service.fetchStandings(tournamentId: tournament.id)
        async let scheduleFetch = service.fetchSchedule(league: league)

        let fetched = (try? await standingsFetch) ?? []
        let schedule = (try? await scheduleFetch) ?? []

        let sorted = applyGD(fetched, schedule: schedule)
        standingsCache[league.id] = sorted
        standings = sorted
    }

    private func preloadFromCache() -> Bool {
        guard let fetched: [League] = AppDiskCache.get(.leagues) else { return false }
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
        guard let tournaments: [Tournament] = AppDiskCache.get(.tournaments(leagueId: league.id)),
              let tournament = activeTournament(from: tournaments),
              let fetched: [Standing] = AppDiskCache.get(.standings(tournamentId: tournament.id))
        else { return nil }
        tournamentIdByLeague[league.id] = tournament.id
        let schedule: [Match] = AppDiskCache.get(.schedule(leagueId: league.id)) ?? []
        return applyGD(fetched, schedule: schedule)
    }

    func applyGD(_ standings: [Standing], schedule: [Match]) -> [Standing] {
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
        let withGD = standings.map { s -> Standing in
            var s = s
            let code = s.team.code.uppercased()
            s.gameWins = gameWinsMap[code] ?? 0
            s.gameLosses = gameLossesMap[code] ?? 0
            return s
        }

        // 케스파컵처럼 Riot Standings API가 전 팀을 0승 0패로 묶어 내려주는 대회 대응:
        // 완료된 경기 결과로 승패를 직접 계산하고, 그 기준으로 그룹별 순위를 재부여한다.
        // 정상적으로 개별 승패가 내려오는 리그(대부분)는 Riot 원본 순위·타이브레이크를 그대로 사용한다.
        guard !withGD.isEmpty, !completed.isEmpty,
              withGD.allSatisfy({ $0.wins + $0.losses == 0 })
        else {
            return withGD.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.wins != $1.wins { return $0.wins > $1.wins }
                if $0.gameDiff != $1.gameDiff { return $0.gameDiff > $1.gameDiff }
                return $0.team.name < $1.team.name
            }
        }
        return recomputeRecordsAndRanks(withGD, completed: completed)
    }

    /// 완료된 경기로부터 팀별 승패를 직접 집계하고, 그룹별로 승수 → 세트 득실 → 팀명 순 정렬해
    /// 순번을 다시 매긴다 (Riot이 동률로 묶어 내려준 rank를 실제 성적 기준 순위로 대체).
    func recomputeRecordsAndRanks(_ standings: [Standing], completed: [Match]) -> [Standing] {
        var wins: [String: Int] = [:]
        var losses: [String: Int] = [:]
        for match in completed {
            let aCode = match.teamA.code.uppercased()
            let bCode = match.teamB.code.uppercased()
            if match.scoreA > match.scoreB {
                wins[aCode, default: 0] += 1
                losses[bCode, default: 0] += 1
            } else if match.scoreB > match.scoreA {
                wins[bCode, default: 0] += 1
                losses[aCode, default: 0] += 1
            }
        }

        let recomputed = standings.map { s -> Standing in
            let code = s.team.code.uppercased()
            let w = wins[code] ?? 0
            let l = losses[code] ?? 0
            let total = w + l
            return Standing(team: s.team, wins: w, losses: l, rank: s.rank,
                             winRate: total > 0 ? Double(w) / Double(total) : 0,
                             gameWins: s.gameWins, gameLosses: s.gameLosses, group: s.group)
        }

        let groups = Dictionary(grouping: recomputed, by: { $0.group })
        var reranked: [Standing] = []
        for (_, group) in groups {
            let sorted = group.sorted {
                if $0.wins != $1.wins { return $0.wins > $1.wins }
                if $0.gameDiff != $1.gameDiff { return $0.gameDiff > $1.gameDiff }
                return $0.team.name < $1.team.name
            }
            for (idx, s) in sorted.enumerated() {
                reranked.append(Standing(team: s.team, wins: s.wins, losses: s.losses, rank: idx + 1,
                                          winRate: s.winRate, gameWins: s.gameWins,
                                          gameLosses: s.gameLosses, group: s.group))
            }
        }
        return reranked.sorted {
            if $0.group != $1.group { return ($0.group ?? "") < ($1.group ?? "") }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
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
