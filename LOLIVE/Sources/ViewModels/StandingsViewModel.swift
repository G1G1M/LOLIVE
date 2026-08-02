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

        // 순위(특히 LCK 레전드/라이즈 그룹처럼 스플릿 넘어 누적되는 표)는 fetchSchedule의 좁은
        // 윈도우로는 부족해서, 시즌 전체를 순회하는 fetchAllSchedule을 쓴다.
        async let standingsFetch = service.fetchStandings(tournamentId: tournament.id)
        async let scheduleFetch = service.fetchAllSchedule(league: league)

        let fetched = (try? await standingsFetch) ?? []
        let schedule = (try? await scheduleFetch) ?? []

        let sorted = applyGD(
            fetched, schedule: schedule,
            seasonStartDate: seasonStartDate(from: tournaments, active: tournament)
        )
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
        let schedule: [Match] = AppDiskCache.get(.allSchedule(leagueId: league.id))
            ?? AppDiskCache.get(.schedule(leagueId: league.id)) ?? []
        return applyGD(
            fetched, schedule: schedule,
            seasonStartDate: seasonStartDate(from: tournaments, active: tournament)
        )
    }

    /// GD·승패를 완료 경기 스코어로 직접 재계산 — 자세한 이유는 Standing.reconciled(_:schedule:) 참고.
    func applyGD(_ standings: [Standing], schedule: [Match], seasonStartDate: Date) -> [Standing] {
        Standing.reconciled(standings, schedule: schedule, seasonStartDate: seasonStartDate)
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
