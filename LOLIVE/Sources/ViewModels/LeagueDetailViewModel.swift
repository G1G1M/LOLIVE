//
//  LeagueDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation
import os

private let standingsLogger = Logger(subsystem: "com.lolive", category: "Standings")
private let navDebugLogger = Logger(subsystem: "com.lolive", category: "NavDebug")

@MainActor
@Observable
final class LeagueDetailViewModel {

    // MARK: - Tab

    enum Tab: CaseIterable {
        case standings, schedule, teams, players, history

        var title: String {
            switch self {
            case .standings: return "순위"
            case .schedule:  return "일정"
            case .teams:     return "팀"
            case .players:   return "선수"
            case .history:   return "기록"
            }
        }
    }
    
    // MARK: - Properties

    var selectedTab: Tab = .standings
    var showBracket: Bool = false
    var standings: [Standing] = []
    var loadFailed = false

    // MARK: - 기록(과거 시즌) 탭

    var historicalYears: [Int] = []
    var selectedHistoricalYear: Int? = nil
    var historicalMatches: [Match] = []
    var isLoadingHistoricalYears = false
    var isLoadingHistoricalMatches = false
    /// "로딩 시작 전(false)"과 "로딩 끝났는데 데이터가 진짜 없음(true, historicalYears 비어있음)"을
    /// 구분하기 위한 플래그. 없으면 탭 진입 첫 프레임에 `isLoadingHistoricalYears`가 아직 false라
    /// "기록 없음" 빈 화면이 잠깐 떴다가 로딩 스피너로, 다시 실제 목록으로 바뀌는 3단 점프가 발생함
    /// (겹쳐 보이면 위→아래로 화면이 미끄러지는 것처럼 보인다는 피드백으로 발견).
    var hasAttemptedHistoricalLoad = false
    /// 선택된 연도 안에서 라운드(플레이오프/그룹 스테이지 등)로 좁혀 볼 수 있게 — nil이면 전체.
    var selectedHistoricalRound: String? = nil

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
    var isLoading = true
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
        #if DEBUG
        navDebugLogger.debug("🔍 [NavDebug] LeagueDetailViewModel.load() 시작 league=\(self.league.name)")
        #endif
        let hadCache = await preloadFromCache()
        isLoading = !hadCache
        loadFailed = false
        defer { isLoading = false }

        // 일정 + 토너먼트 병렬 조회
        async let scheduleTask = service.fetchSchedule(league: league)
        async let tournamentsTask = service.fetchTournaments(leagueId: league.id)
        let scheduleFetch    = try? await scheduleTask
        let tournamentsFetch = try? await tournamentsTask
        guard !Task.isCancelled else {
            #if DEBUG
            navDebugLogger.debug("🔍 [NavDebug] load() 취소됨(체크포인트1) league=\(self.league.name)")
            #endif
            return
        }

        if scheduleFetch == nil && tournamentsFetch == nil && !hadCache {
            if !(await preloadFromStaleCache()) {
                loadFailed = true
            }
            return
        }

        let allMatches  = scheduleFetch    ?? []
        let tournaments = tournamentsFetch ?? []

        let now = Date()
        upcomingMatches = allMatches
            .filter { $0.startTime >= now && $0.state == .unstarted }
            .sorted { $0.startTime < $1.startTime }
        completedMatches = allMatches
            .filter { $0.state == .completed }
            .sorted { $0.startTime > $1.startTime }

        // 최근 완료 경기 상세 데이터 백그라운드 프리로드
        for match in completedMatches.prefix(MatchDetailViewModel.preloadCount) {
            MatchDetailViewModel.preload(match: match)
        }

        // 현재 토너먼트로 순위 + 선수 조회
        guard let tournament = activeTournament(from: tournaments) else { return }

        // 여기서부터가 이 화면에서 가장 무거운 부분(시즌 전체 일정+순위+전 팀 로스터) — 사용자가
        // 이미 화면을 벗어났으면(뒤로가기) 계속 돌면서 상태를 갱신할 필요가 없다. 특히 리그 상세는
        // 화면을 이탈해도 이 뒷부분이 계속 실행되며 매번 @Observable 상태를 갱신해 뒤로가기
        // 전환 애니메이션 도중에도 재렌더링이 걸려 화면이 뚝뚝 끊기는 원인이 됐다(실측 확인).
        guard !Task.isCancelled else {
            #if DEBUG
            navDebugLogger.debug("🔍 [NavDebug] load() 취소됨(체크포인트2) league=\(self.league.name)")
            #endif
            return
        }

        // 순위(특히 LCK 레전드/라이즈 그룹처럼 스플릿 넘어 누적되는 표)는 fetchSchedule의 좁은
        // 윈도우로는 부족해서, 시즌 전체를 순회하는 fetchAllSchedule로 따로 가져온다.
        let seasonMatches = (try? await service.fetchAllSchedule(league: league)) ?? allMatches
        let fetchedStandings = (try? await service.fetchStandings(tournamentId: tournament.id)) ?? []
        let seasonStart = seasonStartDate(from: tournaments, active: tournament)
        #if DEBUG
        let seasonCompletedCount = seasonMatches.filter { $0.state == .completed && $0.startTime >= seasonStart }.count
        standingsLogger.debug("""
            🏆 [Standings] \(self.league.name) tournament=\(tournament.slug) seasonStart=\(seasonStart.description) \
            seasonMatches=\(seasonMatches.count) seasonCompleted=\(seasonCompletedCount)
            """)
        #endif
        standings = applyGD(fetchedStandings, schedule: seasonMatches, seasonStartDate: seasonStart)
        #if DEBUG
        for s in standings {
            standingsLogger.debug("🏆 [Standings]   \(s.group ?? "-") #\(s.rank) \(s.team.code) \(s.wins)승\(s.losses)패 GD\(s.gameDiff)")
        }
        #endif

        guard !Task.isCancelled else {
            #if DEBUG
            navDebugLogger.debug("🔍 [NavDebug] load() 취소됨(체크포인트3) league=\(self.league.name)")
            #endif
            return
        }

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

        guard !Task.isCancelled else {
            #if DEBUG
            navDebugLogger.debug("🔍 [NavDebug] load() 취소됨(체크포인트4) league=\(self.league.name)")
            #endif
            return
        }

        players = filteredPlayers.sorted {
            let r0 = RoleStyle.order($0.role), r1 = RoleStyle.order($1.role)
            return r0 != r1 ? r0 < r1 : $0.summonerName < $1.summonerName
        }
        AppDiskCache.set(key: "league_players_\(league.id)", value: players)
        #if DEBUG
        navDebugLogger.debug("🔍 [NavDebug] load() 끝까지 완료(취소 안 됨) league=\(self.league.name) players=\(self.players.count)")
        #endif
    }

    // MARK: - 기록(과거 시즌) 탭

    /// 과거 시즌이 존재하는 연도 목록을 서버(Firestore 백필 데이터)에서 조회.
    /// Leaguepedia를 직접 호출하지 않는다 — 백필이 안 된 리그는 빈 목록으로 온다.
    func loadHistoricalYears() async {
        hasAttemptedHistoricalLoad = true
        guard historicalYears.isEmpty,
              let leagueName = LeaguepediaService.shared.leaguepediaName(for: league)
        else { return }
        isLoadingHistoricalYears = true
        defer { isLoadingHistoricalYears = false }

        historicalYears = await FirebaseHistoricalService.fetchYears(leagueName: leagueName)
        if selectedHistoricalYear == nil {
            selectedHistoricalYear = historicalYears.first
        }
        if let year = selectedHistoricalYear {
            await loadHistoricalMatches(year: year)
        }
    }

    func selectHistoricalYear(_ year: Int) {
        guard selectedHistoricalYear != year else { return }
        selectedHistoricalYear = year
        historicalMatches = []
        selectedHistoricalRound = nil
        Task { await loadHistoricalMatches(year: year) }
    }

    var availableHistoricalRounds: [Match.RoundGroup] {
        Match.roundGroups(from: historicalMatches)
    }

    private func loadHistoricalMatches(year: Int) async {
        guard let leagueName = LeaguepediaService.shared.leaguepediaName(for: league) else { return }
        isLoadingHistoricalMatches = true
        defer { isLoadingHistoricalMatches = false }
        historicalMatches = await FirebaseHistoricalService.fetchMatches(leagueName: leagueName, year: year)
            .sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Private

    /// 캐시 프리로드 결과 — readDiskPreload()가 백그라운드에서 읽어온 값을 메인 액터로 옮길 때 쓰는 그릇.
    private struct DiskPreload {
        let upcomingMatches: [Match]
        let completedMatches: [Match]
        let standings: [Standing]?
        let players: [Player]?
    }

    /// 캐시 파일 읽기(동기 디스크 I/O + JSON 디코딩, 최대 5개 파일)를 메인 스레드 밖에서 수행한다.
    /// 예전엔 이 로직 전체가 메인 액터(`preloadFromCache()`)에서 그대로 동기 실행돼서, 리그 상세
    /// 화면으로 들어가는 NavigationStack push 애니메이션이 시작되는 바로 그 순간(`.task`가 뷰
    /// 등장과 동시에 호출됨) 메인 스레드가 여러 번의 파일 읽기로 막혀 전환이 뚝뚝 끊기는 문제가
    /// 있었음(리그 상세는 일정+토너먼트+순위+선수까지 한 번에 읽어서 다른 화면보다 유독 무거움).
    private nonisolated static func readDiskPreload(league: League, stale: Bool) -> DiskPreload? {
        let allMatches: [Match]? = stale
            ? AppDiskCache.getStale(.schedule(leagueId: league.id))
            : AppDiskCache.get(.schedule(leagueId: league.id))
        guard let allMatches else { return nil }

        let now = Date()
        let upcoming = allMatches
            .filter { $0.startTime >= now && $0.state == .unstarted }
            .sorted { $0.startTime < $1.startTime }
        let completed = allMatches
            .filter { $0.state == .completed }
            .sorted { $0.startTime > $1.startTime }

        var standings: [Standing]? = nil
        let tournaments: [Tournament]? = stale
            ? AppDiskCache.getStale(.tournaments(leagueId: league.id))
            : AppDiskCache.get(.tournaments(leagueId: league.id))
        if let tournaments, let tournament = activeTournament(from: tournaments) {
            let fetched: [Standing]? = stale
                ? AppDiskCache.getStale(.standings(tournamentId: tournament.id))
                : AppDiskCache.get(.standings(tournamentId: tournament.id))
            if let fetched {
                let seasonMatches: [Match] = (stale
                    ? AppDiskCache.getStale(.allSchedule(leagueId: league.id))
                    : AppDiskCache.get(.allSchedule(leagueId: league.id))) ?? allMatches
                standings = Standing.reconciled(
                    fetched, schedule: seasonMatches,
                    seasonStartDate: seasonStartDate(from: tournaments, active: tournament)
                )
            }
        }

        // stale 경로는 예전에도 선수 캐시를 안 읽었음(원본 동작 유지)
        let players: [Player]? = stale ? nil
            : AppDiskCache.get(key: "league_players_\(league.id)", maxAge: 12 * 3600)

        return DiskPreload(upcomingMatches: upcoming, completedMatches: completed, standings: standings, players: players)
    }

    private func preloadFromCache() async -> Bool {
        guard let result = await Task.detached(priority: .userInitiated) { [league] in
            Self.readDiskPreload(league: league, stale: false)
        }.value else { return false }
        upcomingMatches = result.upcomingMatches
        completedMatches = result.completedMatches
        if let standings = result.standings { self.standings = standings }
        if let players = result.players { self.players = players }
        return true
    }

    private func preloadFromStaleCache() async -> Bool {
        guard let result = await Task.detached(priority: .userInitiated) { [league] in
            Self.readDiskPreload(league: league, stale: true)
        }.value else { return false }
        upcomingMatches = result.upcomingMatches
        completedMatches = result.completedMatches
        if let standings = result.standings { self.standings = standings }
        return true
    }

    /// GD·승패를 완료 경기 스코어로 직접 재계산 — 자세한 이유는 Standing.reconciled(_:schedule:) 참고.
    private func applyGD(_ standings: [Standing], schedule: [Match], seasonStartDate: Date) -> [Standing] {
        Standing.reconciled(standings, schedule: schedule, seasonStartDate: seasonStartDate)
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

