//
//  StandingsViewModel.swift
//  LOLIVE
//

import Foundation
import Observation
import os

private let standingsLogger = Logger(subsystem: "com.lolive", category: "Standings")

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

    private nonisolated static let excludedRegions: Set<String> = ["국제 대회"]
    private nonisolated static let secondaryKeywords = ["챌린저스", "challengers", "academy", "circuito desafiante"]

    // MARK: - Init

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
    }

    // MARK: - Public

    func loadLeagues() async {
        // 캐시 읽기가 비동기라 로딩 표시를 먼저 켜둔다(빈 상태가 한 프레임 스치는 것 방지).
        isLoadingLeagues = leagues.isEmpty
        loadFailed = false
        defer { isLoadingLeagues = false }
        let hadCache = await preloadFromCache()
        if hadCache { isLoadingLeagues = false }

        let fetchResult = try? await service.fetchLeagues()
        if let fetched = fetchResult {
            leagues = Self.displayableLeagues(fetched)
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

        let diskCached = await Task.detached(priority: .userInitiated) { [league] in
            Self.readCachedStandings(for: league)
        }.value
        if let diskCached {
            tournamentIdByLeague[league.id] = diskCached.tournamentId
            standings = diskCached.standings
            standingsCache[league.id] = diskCached.standings
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

        let seasonStart = seasonStartDate(from: tournaments, active: tournament)
        #if DEBUG
        let seasonCompletedCount = schedule.filter { $0.state == .completed && $0.startTime >= seasonStart }.count
        standingsLogger.debug("""
            🏆 [Standings] \(league.name) tournament=\(tournament.slug) seasonStart=\(seasonStart.description) \
            seasonMatches=\(schedule.count) seasonCompleted=\(seasonCompletedCount)
            """)
        #endif
        let sorted = applyGD(fetched, schedule: schedule, seasonStartDate: seasonStart)
        #if DEBUG
        for s in sorted {
            standingsLogger.debug("🏆 [Standings]   \(s.group ?? "-") #\(s.rank) \(s.team.code) \(s.wins)승\(s.losses)패 GD\(s.gameDiff)")
        }
        #endif
        standingsCache[league.id] = sorted
        standings = sorted
    }

    /// 순위 화면에 노출할 리그만 남기고 지역 순으로 정렬한다.
    /// API 응답 경로와 캐시 선로딩 경로가 정확히 같은 목록을 만들어야 해서 한 곳에 모아둔다.
    nonisolated static func displayableLeagues(_ leagues: [League]) -> [League] {
        leagues
            .filter { !excludedRegions.contains($0.region) }
            .filter { league in
                let name = league.name.lowercased()
                return !secondaryKeywords.contains(where: { name.contains($0) })
            }
            .sorted { regionOrder($0.region) < regionOrder($1.region) }
    }

    /// 캐시 프리로드 결과 — 백그라운드에서 읽은 값을 메인 액터로 옮길 때 쓰는 그릇.
    private struct DiskPreload {
        let leagues: [League]
        let firstLeague: League
        let tournamentId: String?
        let standings: [Standing]?
    }

    /// 리그 목록 → 첫 리그의 토너먼트·순위·전체 스케줄까지 파일 4개를 읽고 GD 재계산까지 한다.
    /// 전체 스케줄만 실측 330KB라 메인 액터에서 돌리면 순위 탭 첫 진입이 그만큼 늦어진다 —
    /// 읽기·디코딩·재계산 전부 `nonisolated`로 두고 백그라운드에서 실행한다.
    private nonisolated static func readDiskPreload() -> DiskPreload? {
        guard let fetched: [League] = AppDiskCache.get(.leagues) else { return nil }
        let filtered = displayableLeagues(fetched)
        guard let first = filtered.first else { return nil }

        guard let cached = readCachedStandings(for: first) else {
            return DiskPreload(leagues: filtered, firstLeague: first, tournamentId: nil, standings: nil)
        }
        return DiskPreload(leagues: filtered, firstLeague: first,
                           tournamentId: cached.tournamentId, standings: cached.standings)
    }

    /// 한 리그의 토너먼트·순위·전체 스케줄 캐시를 읽고 GD를 재계산한다.
    /// 전체 스케줄만 실측 330KB라, 리그를 바꿀 때마다 메인 액터에서 돌리면 그만큼 화면이 멈춘다.
    nonisolated static func readCachedStandings(for league: League) -> (tournamentId: String, standings: [Standing])? {
        guard let tournaments: [Tournament] = AppDiskCache.get(.tournaments(leagueId: league.id)),
              let tournament = activeTournament(from: tournaments),
              let cached: [Standing] = AppDiskCache.get(.standings(tournamentId: tournament.id))
        else { return nil }

        let schedule: [Match] = AppDiskCache.get(.allSchedule(leagueId: league.id))
            ?? AppDiskCache.get(.schedule(leagueId: league.id)) ?? []
        let reconciled = Standing.reconciled(
            cached, schedule: schedule,
            seasonStartDate: seasonStartDate(from: tournaments, active: tournament)
        )
        return (tournament.id, reconciled)
    }

    private func preloadFromCache() async -> Bool {
        let preload = await Task.detached(priority: .userInitiated) {
            Self.readDiskPreload()
        }.value
        guard let result = preload else { return false }
        leagues = result.leagues
        selectedLeague = result.firstLeague
        if let tournamentId = result.tournamentId {
            tournamentIdByLeague[result.firstLeague.id] = tournamentId
        }
        if let cached = result.standings {
            standings = cached
            standingsCache[result.firstLeague.id] = cached
        }
        return true
    }

    /// GD·승패를 완료 경기 스코어로 직접 재계산 — 자세한 이유는 Standing.reconciled(_:schedule:) 참고.
    func applyGD(_ standings: [Standing], schedule: [Match], seasonStartDate: Date) -> [Standing] {
        Standing.reconciled(standings, schedule: schedule, seasonStartDate: seasonStartDate)
    }

    private nonisolated static func regionOrder(_ region: String) -> Int {
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
