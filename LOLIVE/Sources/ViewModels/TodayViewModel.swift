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
    private var pollingTask: Task<Void, Never>?
    private var cachedLeagues: [League] = []

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }()

    // MARK: - Init

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
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

            let service = service
            async let liveResult = service.fetchLive()
            async let scheduleResults = withThrowingTaskGroup(of: [Match].self) { group in
                for league in leagues {
                    group.addTask { try await service.fetchSchedule(league: league) }
                }
                return try await group.reduce(into: [Match]()) { $0.append(contentsOf: $1) }
            }

            let (live, allMatches) = try await (liveResult, scheduleResults)

            liveMatches = enrich(live)
            classify(matches: allMatches)
        } catch {
            errorMessage = errorDescription(error)
        }

        isLoading = false
    }

    func startLivePolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                // 즐겨찾기 팀의 현재 라이브 경기 스냅샷 (종료 감지용)
                let prevFavoriteLive = liveMatches.filter { favoriteTeamCode(for: $0.match) != nil }

                do {
                    let live = try await service.fetchLive()
                    let newLiveIds = Set(live.map { $0.match.id })

                    // 라이브에서 사라진 즐겨찾기 경기 → 결과 알림
                    for lm in prevFavoriteLive where !newLiveIds.contains(lm.match.id) {
                        if let code = favoriteTeamCode(for: lm.match) {
                            await MatchNotificationService.shared.sendResultNotification(
                                for: lm.match, favoriteTeamCode: code
                            )
                        }
                    }

                    liveMatches = enrich(live)
                    await LiveActivityService.shared.syncActivities(liveMatches, favoritedTeamIds: favoritedTeamIds)
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
        let svc = service
        Task {
            if let fresh = try? await svc.fetchLive() {
                let enriched = enrich(fresh)
                liveMatches = enriched
                await LiveActivityService.shared.syncActivities(enriched, favoritedTeamIds: favoritedTeamIds)
            } else {
                await LiveActivityService.shared.syncActivities(liveMatches, favoritedTeamIds: favoritedTeamIds)
            }
        }
    }

    // MARK: - Private

    private func preloadFromCache() -> Bool {
        guard let leagues: [League] = AppDiskCache.get(key: "leagues", maxAge: 24 * 3600) else { return false }
        var allMatches: [Match] = []
        for league in leagues {
            if let matches: [Match] = AppDiskCache.get(key: "schedule_\(league.id)", maxAge: 15 * 60) {
                allMatches.append(contentsOf: matches)
            }
        }
        cachedLeagues = leagues
        classify(matches: allMatches)
        return true
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
            return LiveMatch(match: enrichedMatch, currentSet: lm.currentSet, lastUpdated: lm.lastUpdated)
        }
    }

    private func classify(matches: [Match]) {
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        guard let todayEnd      = calendar.date(byAdding: .day, value:  1, to: todayStart),
              let fiveDaysAhead = calendar.date(byAdding: .day, value:  6, to: todayStart),
              let fiveDaysAgo   = calendar.date(byAdding: .day, value: -5, to: todayStart)
        else { return }

        // 오늘 아직 시작 안 한 경기
        todayMatches = matches.filter {
            $0.startTime >= todayStart && $0.startTime < todayEnd && $0.state == .unstarted
        }.sorted { $0.startTime < $1.startTime }

        // 내일~5일 후 예정 경기 (날짜 스트립 +5일 대응)
        upcomingMatches = matches.filter {
            $0.startTime >= todayEnd && $0.startTime < fiveDaysAhead && $0.state == .unstarted
        }.sorted { $0.startTime < $1.startTime }

        // 5일 전~오늘 완료 경기 (날짜 스트립 -5일 대응)
        completedMatches = matches.filter {
            $0.state == .completed && $0.startTime >= fiveDaysAgo
        }.sorted { $0.startTime > $1.startTime }
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
