//
//  TodayViewModel.swift
//  LOLIVE
//

import Foundation
import Observation
import os

private let livePollLogger = Logger(subsystem: "com.lolive", category: "LivePoll")

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

    /// 즐겨찾기 팀 목록(ID+코드+리그) — ContentView에서 SwiftData 쿼리 결과로 설정
    var favoritedTeams: Set<FavoritedTeamRef> = []


    // MARK: - Private

    let service: RiotEsportsServiceProtocol
    let liveStatsService: LiveStatsServiceProtocol
    var pollingTask: Task<Void, Never>?
    var syncTask: Task<Void, Never>?
    var reconcileTask: Task<Void, Never>?
    var cachedLeagues: [League] = []

    // 라이브 스탯 피드가 멈췄는지 판단하기 위한 상태 (즐겨찾기 라이브 경기 전용)
    var lastStuckCheck: [String: Date] = [:]              // matchId -> 마지막으로 Leaguepedia 대조한 시각
    // matchId -> Leaguepedia로 보정한 최신 상태. state == .completed면 시리즈 전체 종료 확정,
    // 그 외엔 세트 단위로 스코어만 보정된 상태(시리즈는 계속 진행 중)라 liveMatches에 계속 반영한다.
    var leaguepediaOverrides: [String: Match] = [:]
    static let staleFeedThreshold: TimeInterval = 5 * 60  // 라이브 피드 프레임이 이보다 오래 안 갱신되면 "멈춤"
    static let stuckRecheckCooldown: TimeInterval = 5 * 60

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

    /// - Parameter forceRefresh: true면 일정 캐시(15분 TTL)를 무시하고 강제로 새로 받아온다.
    ///   당겨서 새로고침(pull-to-refresh)이 캐시 때문에 실제로는 아무것도 안 바뀌는 문제를 막기 위함.
    ///
    ///   Leaguepedia 결과 캐시(fetchLiveTournamentResults, 15분)는 여기서 따로 안 지운다 — 한때
    ///   추적 중인 모든 리그에 대해 한꺼번에 지우려고 시도했었는데, 리그 수가 많다 보니 새로고침
    ///   한 번에 Leaguepedia를 왕창 두드리게 돼서 서버 레이트리밋에 걸려 오히려 결과가 랜덤하게
    ///   실패하는 부작용이 있었다. 일정 캐시만 지워도 reconcileUnreportedResults가 다시 돌면서
    ///   실제로 대조가 필요한 리그에 한해서만(hasStale 조건) 자연스럽게 Leaguepedia를 호출한다.
    func loadTodayMatches(forceRefresh: Bool = false) async {
        if forceRefresh {
            for league in cachedLeagues {
                AppDiskCache.clear(.schedule(leagueId: league.id))
            }
        } else if !preloadFromCache() {
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

            // 1단계: Riot 원본으로 화면을 즉시 채운다 (Leaguepedia 보정을 기다리지 않음 — 여러 리그가
            // 동시에 보정이 필요한 상황이면 레이트리밋 재시도로 리그당 최대 36초까지 걸릴 수 있는데,
            // 그걸 화면 전체가 기다리게 하지 않기 위함)
            let rawMatches = try await withThrowingTaskGroup(of: [Match].self) { group in
                for league in leagues {
                    group.addTask { try await svc.fetchScheduleRaw(league: league) }
                }
                return try await group.reduce(into: [Match]()) { $0.append(contentsOf: $1) }
            }
            classify(matches: rawMatches)
            isLoading = false

            // 2단계: Leaguepedia 보정까지 포함한 결과를 백그라운드에서 마저 받아와서, 끝나는 대로
            // 화면을 한 번 더 갱신한다. fetchSchedule은 캐시가 이미 있으면 캐시를 즉시 반환하므로
            // 보정이 필요 없는 대부분의 상황에서는 이 2단계가 사실상 즉시 끝난다.
            reconcileTask?.cancel()
            reconcileTask = Task {
                let reconciled = try? await withThrowingTaskGroup(of: [Match].self) { group in
                    for league in leagues {
                        group.addTask { try await svc.fetchSchedule(league: league) }
                    }
                    return try await group.reduce(into: [Match]()) { $0.append(contentsOf: $1) }
                }
                guard let reconciled, !Task.isCancelled else { return }
                classify(matches: reconciled)
            }
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


    // MARK: - Private


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
