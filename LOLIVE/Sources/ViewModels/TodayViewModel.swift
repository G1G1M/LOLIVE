//
//  TodayViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {

    // MARK: - Properties

    var liveMatches: [LiveMatch] = []
    var todayMatches: [Match] = []
    var upcomingMatches: [Match] = []
    var completedMatches: [Match] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var showAllCompleted: Bool = false
    let completedMatchesLimit = 5
    var showFavoritesOnly: Bool = false

    /// 즐겨찾기 팀 ID + Code 집합 — ContentView에서 SwiftData 쿼리 결과로 설정
    var favoritedTeamIds: Set<String> = []

    var hasFavoriteTeams: Bool { !favoritedTeamIds.isEmpty }

    var filteredLiveMatches: [LiveMatch] {
        guard showFavoritesOnly else { return liveMatches }
        return liveMatches.filter { isFavorited($0.match) }
    }

    var filteredTodayMatches: [Match] {
        guard showFavoritesOnly else { return todayMatches }
        return todayMatches.filter { isFavorited($0) }
    }

    var filteredUpcomingMatches: [Match] {
        guard showFavoritesOnly else { return upcomingMatches }
        return upcomingMatches.filter { isFavorited($0) }
    }

    var filteredCompletedMatches: [Match] {
        guard showFavoritesOnly else { return completedMatches }
        return completedMatches.filter { isFavorited($0) }
    }

    var displayedCompletedMatches: [Match] {
        let all = filteredCompletedMatches
        return showAllCompleted ? all : Array(all.prefix(completedMatchesLimit))
    }

    var hasMoreCompleted: Bool {
        !showAllCompleted && filteredCompletedMatches.count > completedMatchesLimit
    }

    var isFavoritesFilterEmpty: Bool {
        showFavoritesOnly &&
        filteredLiveMatches.isEmpty &&
        filteredTodayMatches.isEmpty &&
        filteredUpcomingMatches.isEmpty &&
        filteredCompletedMatches.isEmpty
    }


    private func isFavorited(_ match: Match) -> Bool {
        favoritedTeamIds.contains(match.teamA.id) || favoritedTeamIds.contains(match.teamB.id)
    }

    private func favoriteTeamCode(for match: Match) -> String? {
        if favoritedTeamIds.contains(match.teamA.id) || favoritedTeamIds.contains(match.teamA.code) {
            return match.teamA.code
        }
        if favoritedTeamIds.contains(match.teamB.id) || favoritedTeamIds.contains(match.teamB.code) {
            return match.teamB.code
        }
        return nil
    }

    // MARK: - Private

    private let service: RiotEsportsServiceProtocol
    private let liveStatsService: LiveStatsServiceProtocol
    private var pollingTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var cachedLeagues: [League] = []

    // 라이브 스탯 피드가 멈췄는지 판단하기 위한 상태 (즐겨찾기 라이브 경기 전용)
    private var lastStuckCheck: [String: Date] = [:]              // matchId -> 마지막으로 Leaguepedia 대조한 시각
    // matchId -> Leaguepedia로 보정한 최신 상태. state == .completed면 시리즈 전체 종료 확정,
    // 그 외엔 세트 단위로 스코어만 보정된 상태(시리즈는 계속 진행 중)라 liveMatches에 계속 반영한다.
    private var leaguepediaOverrides: [String: Match] = [:]
    private static let staleFeedThreshold: TimeInterval = 5 * 60  // 라이브 피드 프레임이 이보다 오래 안 갱신되면 "멈춤"
    private static let stuckRecheckCooldown: TimeInterval = 5 * 60

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }()

    // MARK: - Init

    init(service: RiotEsportsServiceProtocol = RiotEsportsService(),
         liveStatsService: LiveStatsServiceProtocol = LiveStatsService()) {
        self.service = service
        self.liveStatsService = liveStatsService
    }

    // MARK: - Public

    func loadTodayMatches() async {
        if !preloadFromCache() {
            isLoading = true
        }
        errorMessage = nil

        do {
            let leagues = try await service.fetchLeagues()
            cachedLeagues = leagues

            let svc = service

            // live fetch는 스케줄과 독립적으로 실행 — 실패해도 스케줄 표시에 영향 없음
            Task {
                if let live = try? await svc.fetchLive() {
                    liveMatches = enrich(live)
                }
            }

            let allMatches = try await withThrowingTaskGroup(of: [Match].self) { group in
                for league in leagues {
                    group.addTask { try await svc.fetchSchedule(league: league) }
                }
                return try await group.reduce(into: [Match]()) { $0.append(contentsOf: $1) }
            }
            classify(matches: allMatches)
        } catch {
            // 화면에 데이터가 전혀 없을 때만 에러 표시
            // 캐시 데이터가 이미 있으면 에러 알림 없이 유지
            let hasData = !todayMatches.isEmpty || !completedMatches.isEmpty || !upcomingMatches.isEmpty
            if !hasData && !loadFromStaleCache() {
                errorMessage = errorDescription(error)
            }
        }

        isLoading = false
    }

    func startLivePolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                // 종료 감지용 스냅샷 (전체 라이브 경기 + 즐겨찾기 팀 경기)
                let prevLive = liveMatches
                let prevFavoriteLive = prevLive.filter { favoriteTeamCode(for: $0.match) != nil }

                do {
                    let live = try await service.fetchLive()
                    let newLiveIds = Set(live.map { $0.match.id })
                    let newFavoriteLive = live.filter { favoriteTeamCode(for: $0.match) != nil }

                    // 라이브에서 사라진 즐겨찾기 경기 → 결과 알림
                    for lm in prevFavoriteLive where !newLiveIds.contains(lm.match.id) {
                        if let code = favoriteTeamCode(for: lm.match) {
                            await MatchNotificationService.shared.sendResultNotification(
                                for: lm.match, favoriteTeamCode: code
                            )
                        }
                    }

                    // 즐겨찾기 경기의 시작/세트 진행 알림
                    // (Leaguepedia로 이미 시리즈 완료 확정된 경기는 제외 — Riot이 아직 안 따라잡아 live에 남아있어도
                    //  prevFavoriteLive엔 없으므로 "새로 시작"으로 오판하지 않도록 가드. 세트 단위 보정만 된
                    //  경기는 여전히 진행 중이라 이 루프를 계속 타야 하므로 제외하지 않는다)
                    for lm in newFavoriteLive where leaguepediaOverrides[lm.match.id]?.state != .completed {
                        guard let code = favoriteTeamCode(for: lm.match) else { continue }
                        if let prev = prevFavoriteLive.first(where: { $0.match.id == lm.match.id }) {
                            // 세트 번호가 늘었으면 이전 세트 종료 + 새 세트 시작 알림
                            if lm.currentSet > prev.currentSet {
                                await MatchNotificationService.shared.sendSetEndNotification(
                                    for: lm.match, favoriteTeamCode: code, endedSet: prev.currentSet
                                )
                                await MatchNotificationService.shared.sendSetStartNotification(
                                    for: lm.match, favoriteTeamCode: code, newSet: lm.currentSet
                                )
                            }
                        } else {
                            // 직전 폴링엔 없었는데 지금 라이브 → 경기 시작
                            await MatchNotificationService.shared.sendMatchStartNotification(
                                for: lm.match, favoriteTeamCode: code
                            )
                        }
                    }

                    // 라이브에서 사라진 모든 경기 → 다음 전체 스케줄 리로드 전까지도
                    // 화면에서 사라지지 않도록 로컬에서 즉시 완료 상태로 승격
                    for lm in prevLive where !newLiveIds.contains(lm.match.id) {
                        markCompleted(lm.match)
                    }

                    // Riot 라이브 목록에서 스스로 빠지면(뒤늦게라도 따라잡으면) override 기록도 정리
                    leaguepediaOverrides = leaguepediaOverrides.filter { newLiveIds.contains($0.key) }
                    lastStuckCheck = lastStuckCheck.filter { newLiveIds.contains($0.key) }

                    // Leaguepedia 보정 적용: 시리즈 완료 확정은 목록에서 제외(이미 markCompleted 처리됨),
                    // 세트 단위 보정은 스코어만 교체해 계속 라이브로 표시
                    liveMatches = enrich(live).compactMap { lm -> LiveMatch? in
                        guard let override = leaguepediaOverrides[lm.match.id] else { return lm }
                        guard override.state != .completed else { return nil }
                        return LiveMatch(match: override, currentSet: lm.currentSet,
                                         lastUpdated: lm.lastUpdated, currentGameId: lm.currentGameId)
                    }
                    checkStuckLiveMatches(newFavoriteLive)

                    // 예약 시각이 지났으나 API 미확인 즐겨찾기 경기 (조기 시작 대응 + API 딜레이 브릿징)
                    let overdueMatches = todayMatches.filter {
                        $0.startTime <= Date() &&
                        $0.state == .unstarted &&
                        favoriteTeamCode(for: $0) != nil &&
                        !newLiveIds.contains($0.id)
                    }
                    await LiveActivityService.shared.syncActivities(liveMatches, overdueMatches: overdueMatches, favoritedTeamIds: favoritedTeamIds)
                } catch {
                    // 폴링 중 에러는 무시 (기존 데이터 유지)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 즐겨찾기 변경 시 폴링 주기를 기다리지 않고 즉시 Live Activity 동기화.
    /// 최신 라이브 데이터를 직접 fetch해서 liveMatches가 오래됐거나 비어 있어도 정확히 동작.
    func syncLiveActivitiesNow() {
        syncTask?.cancel()
        let svc = service
        syncTask = Task {
            if let fresh = try? await svc.fetchLive() {
                let enriched = enrich(fresh)
                liveMatches = enriched
                let liveIds = Set(enriched.map { $0.match.id })
                let overdueMatches = todayMatches.filter {
                    $0.startTime <= Date() &&
                    $0.state == .unstarted &&
                    favoriteTeamCode(for: $0) != nil &&
                    !liveIds.contains($0.id)
                }
                await LiveActivityService.shared.syncActivities(enriched, overdueMatches: overdueMatches, favoritedTeamIds: favoritedTeamIds)
            } else {
                await LiveActivityService.shared.syncActivities(liveMatches, favoritedTeamIds: favoritedTeamIds)
            }
        }
    }

    // MARK: - Private

    private func preloadFromCache() -> Bool {
        guard let leagues: [League] = AppDiskCache.get(.leagues) else { return false }
        var allMatches: [Match] = []
        for league in leagues {
            if let matches: [Match] = AppDiskCache.get(.schedule(leagueId: league.id)) {
                allMatches.append(contentsOf: matches)
            }
        }
        cachedLeagues = leagues
        classify(matches: allMatches)
        return true
    }

    private func loadFromStaleCache() -> Bool {
        guard let leagues: [League] = AppDiskCache.getStale(.leagues) else { return false }
        var allMatches: [Match] = []
        for league in leagues {
            if let matches: [Match] = AppDiskCache.getStale(.schedule(leagueId: league.id)) {
                allMatches.append(contentsOf: matches)
            }
        }
        guard !allMatches.isEmpty else { return false }
        cachedLeagues = leagues
        classify(matches: allMatches)
        return true
    }

    /// 라이브 목록에서 방금 사라진 경기를 완료 상태로 로컬 승격.
    /// 다음 loadTodayMatches() 전체 리로드(스케줄 캐시 15분) 전까지도
    /// todayMatches/upcomingMatches에 남은 stale 항목을 제거하고 completedMatches로 옮긴다.
    func markCompleted(_ match: Match) {
        todayMatches.removeAll { $0.id == match.id }
        upcomingMatches.removeAll { $0.id == match.id }
        guard !completedMatches.contains(where: { $0.id == match.id }) else { return }
        let finished = Match(
            id: match.id, league: match.league,
            teamA: match.teamA, teamB: match.teamB,
            scoreA: match.scoreA, scoreB: match.scoreB,
            startTime: match.startTime, state: .completed,
            blockName: match.blockName
        )
        completedMatches.insert(finished, at: 0)
    }

    /// 즐겨찾기 라이브 경기의 인게임 스탯 피드(feed.lolesports.com)가 멈췄는지 확인.
    ///
    /// [왜 스코어/세트 번호로 판단하지 않는가] 스코어는 한 세트가 끝나야만 바뀌는 값이라
    /// 정상 진행 중에도 20~40분씩 그대로인 게 당연하다 — 그걸로 "멈춤"을 판단하면
    /// 멀쩡히 진행 중인 경기까지 전부 오탐하게 된다. 대신 인게임 피드의 gameState/최신 프레임
    /// 시각을 직접 확인해서, `"finished"`가 명시적으로 찍혀 있거나 오래 조용할 때만 "멈췄다"고 판단한다.
    ///
    /// 멈춘 것으로 확인되면 Leaguepedia MatchSchedule과 대조한다 — 이 테이블은 시리즈가 안 끝나도
    /// Team1Score/Team2Score를 세트가 끝날 때마다 갱신해주므로 부분 스코어(예: 0-1)도 반영 가능하다.
    /// 이전에 이미 반영한 것과 스코어가 같으면(Leaguepedia도 아직 그대로) 재알림을 보내지 않는다.
    /// 아무 데도 없으면 억지로 점수를 만들어내지 않고 다음 쿨다운에 재시도한다.
    private func checkStuckLiveMatches(_ favoriteLive: [LiveMatch]) {
        for lm in favoriteLive {
            guard let gameId = lm.currentGameId else { continue }
            guard leaguepediaOverrides[lm.match.id]?.state != .completed else { continue }
            let lastCheck = lastStuckCheck[lm.match.id]
            guard lastCheck == nil || Date().timeIntervalSince(lastCheck!) > Self.stuckRecheckCooldown else { continue }
            lastStuckCheck[lm.match.id] = Date()

            let match = lm.match
            let currentSet = lm.currentSet
            let stats = liveStatsService
            let previousScore = leaguepediaOverrides[match.id].map { ($0.scoreA, $0.scoreB) }
                ?? (match.scoreA, match.scoreB)
            Task {
                let recentWindowStart = Date().addingTimeInterval(-(Self.staleFeedThreshold + 5 * 60))
                guard let window = try? await stats.fetchGameWindow(gameId: gameId, startingTime: recentWindowStart)
                else { return }
                let isFinished = window.gameState == "finished"
                let isStale = window.lastFrameTimestamp
                    .map { Date().timeIntervalSince($0) > Self.staleFeedThreshold } ?? true
                guard isFinished || isStale else { return }

                guard let updated = await LeaguepediaService.shared.reconcileStuckLiveMatch(match) else { return }
                let newScore = (updated.scoreA, updated.scoreB)
                guard newScore != previousScore else { return }  // Leaguepedia도 아직 그대로면 조용히 재시도만

                leaguepediaOverrides[match.id] = updated
                if updated.state == .completed {
                    liveMatches.removeAll { $0.match.id == match.id }
                    markCompleted(updated)
                    if let code = favoriteTeamCode(for: updated) {
                        await MatchNotificationService.shared.sendResultNotification(for: updated, favoriteTeamCode: code)
                    }
                } else if let code = favoriteTeamCode(for: updated) {
                    await MatchNotificationService.shared.sendSetEndNotification(
                        for: updated, favoriteTeamCode: code, endedSet: currentSet
                    )
                }
            }
        }
    }

    private func enrich(_ live: [LiveMatch]) -> [LiveMatch] {
        let map = Dictionary(uniqueKeysWithValues: cachedLeagues.map { ($0.id, $0.imageURL) })
        return live.map { lm in
            guard let imageURL = map[lm.match.league.id] else { return lm }
            let enrichedLeague = League(
                id: lm.match.league.id, slug: lm.match.league.slug,
                name: lm.match.league.name,
                region: lm.match.league.region, imageURL: imageURL
            )
            let enrichedMatch = Match(
                id: lm.match.id, league: enrichedLeague,
                teamA: lm.match.teamA, teamB: lm.match.teamB,
                scoreA: lm.match.scoreA, scoreB: lm.match.scoreB,
                startTime: lm.match.startTime, state: lm.match.state
            )
            return LiveMatch(match: enrichedMatch, currentSet: lm.currentSet, lastUpdated: lm.lastUpdated, currentGameId: lm.currentGameId)
        }
    }

    func classify(matches: [Match]) {
        let todayStart = calendar.startOfDay(for: Date())
        guard let todayEnd    = calendar.date(byAdding: .day, value:  1, to: todayStart),
              let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: todayStart)
        else { return }


        // 오늘 경기 (예정 + 진행 중). startTime이 이미 지났어도 inProgress면 포함해야
        // 라이브 폴링 중 fetchLive()에서만 빠지는 순간 화면에서 통째로 사라지지 않는다.
        todayMatches = matches.filter {
            $0.startTime >= todayStart && $0.startTime < todayEnd &&
            ($0.state == .unstarted || $0.state == .inProgress)
        }.sorted { $0.startTime < $1.startTime }

        // 내일 이후 모든 예정 경기 — inProgress여도 미래면 upcoming (MSI 토너먼트 블록 대응)
        upcomingMatches = matches.filter {
            $0.startTime >= todayEnd &&
            ($0.state == .unstarted || $0.state == .inProgress)
        }.sorted { $0.startTime < $1.startTime }

        // 5일 전~오늘 완료 경기 (날짜 스트립 -5일 대응)
        completedMatches = matches.filter {
            $0.state == .completed && $0.startTime >= fiveDaysAgo
        }.sorted { $0.startTime > $1.startTime }

        for match in completedMatches.prefix(MatchDetailViewModel.preloadCount) {
            MatchDetailViewModel.preload(match: match)
        }

    }

    private func errorDescription(_ error: Error) -> String {
        switch error {
        case APIError.invalidURL:
            return "잘못된 URL입니다."
        case APIError.requestFailed(let code):
            return "요청 실패 (상태 코드: \(code))"
        case APIError.decodingFailed:
            return "데이터 파싱에 실패했습니다."
        default:
            return "알 수 없는 오류가 발생했습니다."
        }
    }
}
