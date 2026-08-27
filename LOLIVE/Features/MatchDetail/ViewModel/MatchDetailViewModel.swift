//
//  MatchDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation
import os


@MainActor
@Observable
final class MatchDetailViewModel {

    // MARK: - Properties

    var eventDetail: EventDetailInfo? = nil
    var gameWindows: [String: GameWindow] = [:]
    var leaguepediaBans: [String: (team1Bans: [String], team2Bans: [String])] = [:]
    var oeBans: [String: (blue: [String], red: [String])] = [:]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var selectedGameId: String? = nil
    var currentGameTime: Int? = nil   // 인게임 경과 시간 (초)
    var lastPolledAt: Date? = nil     // 마지막 폴링 시각
    var killTimelines: [String: [KillEvent]] = [:]

    // MARK: - Computed

    var selectedGame: GameInfo? {
        guard let detail = eventDetail else { return nil }
        if let selectedGameId {
            return detail.games.first { $0.gameId == selectedGameId }
        }
        // 인게임 → 드래프트 중(unstarted) → 완료 순으로 기본 선택
        return detail.games.first { $0.state == .inProgress }
            ?? detail.games.first { $0.state == .unstarted }
            ?? detail.games.first { $0.state == .completed }
    }

    var selectedGameWindow: GameWindow? {
        guard let game = selectedGame else { return nil }
        return gameWindows[game.gameId]
    }

    /// Riot API 밴 데이터가 없을 경우 Oracle's Elixir → Leaguepedia 순으로 fallback.
    /// OE는 `team100=블루/team200=레드`가 Riot 엔진 표준이라 이미 블루/레드로 나와서 바로 씀.
    /// Leaguepedia는 team1/team2(매치 기준)만 줘서 blueTeamId/redTeamId + teamAEsportsId로
    /// blue/red 매핑이 추가로 필요.
    func correctedBans(for game: GameInfo) -> (blue: [String], red: [String]) {
        if !game.blueBans.isEmpty || !game.redBans.isEmpty {
            return (game.blueBans, game.redBans)
        }
        if let oe = oeBans[game.gameId] {
            return oe
        }
        guard let lp = leaguepediaBans[game.gameId],
              let detail = eventDetail else { return ([], []) }
        if game.blueTeamId == detail.teamAEsportsId {
            return (lp.team1Bans, lp.team2Bans)
        } else {
            return (lp.team2Bans, lp.team1Bans)
        }
    }

    // MARK: - Private

    /// 화면 진입/캐시 경로 추적용 — 분리된 extension 파일에서도 써야 해서 타입 소속으로 둔다.
    nonisolated static let navDebugLogger = Logger(subsystem: "com.lolive", category: "NavDebug")

    let match: Match
    let esportsService: RiotEsportsServiceProtocol
    let liveStatsService: LiveStatsServiceProtocol
    let leaguepediaService = LeaguepediaService()
    var pollingTask: Task<Void, Never>?

    // MARK: - Init

    init(
        match: Match,
        esportsService: RiotEsportsServiceProtocol = RiotEsportsService(),
        liveStatsService: LiveStatsServiceProtocol = LiveStatsService()
    ) {
        self.match = match
        self.esportsService = esportsService
        self.liveStatsService = liveStatsService
    }

    // MARK: - Public

    func load() async {
        #if DEBUG
        Self.navDebugLogger.debug("🔍 [NavDebug] load() 시작 matchId=\(self.match.id) state=\(self.match.state.rawValue)")
        #endif
        // 백필된 과거 시즌 경기(oe_/lp_ 접두사)는 Riot API의 실제 경기 ID가 아니라 상세 조회 자체가
        // 불가능 — Riot 호출 없이 백필 데이터(match.games, 있으면)로 직접 화면을 채운다.
        if Self.isBackfilledMatchId(match.id) {
            loadFromBackfilledGames()
            return
        }

        // 예정 경기: game window 폴링 불필요, eventDetail만 fetch (TeamDetailView 로스터용 실제 team ID 확보)
        if match.state == .unstarted {
            if eventDetail == nil {
                eventDetail = try? await esportsService.fetchEventDetails(matchId: match.id)
            }
            return
        }

        // 완료된 경기: 디스크 캐시 → 서버(Firestore) 캐시 순으로 확인, 있으면 Riot 재호출 없이 표시
        if match.state == .completed {
            // SwiftUI가 NavigationStack 전환 과정에서 같은 화면의 .task를 실제로 두 번 이상
            // 재실행하는 경우가 실측으로 확인됐다(정확한 이유는 못 밝혔지만, 리그로 갔다가
            // 뒤로가기로 돌아올 때 반복 재현됨). 원인을 완전히 못 없애더라도, 이미 로드된
            // 완료 경기라면 아무 것도 다시 안 건드리도록 멱등하게 만들어서 재실행이 상태를
            // 리셋하며 화면(ScrollView 포함)이 다시 그려지는 걸 원천 차단한다.
            guard eventDetail == nil else {
                #if DEBUG
                Self.navDebugLogger.debug("🔍 [NavDebug] load() 이미 로드됨(재실행 스킵) matchId=\(self.match.id)")
                #endif
                return
            }
            if await tryLoadFromCache() {
                #if DEBUG
                Self.navDebugLogger.debug("🔍 [NavDebug] load() 디스크 캐시 경로로 완료 matchId=\(self.match.id)")
                #endif
                return
            }
            if await tryLoadFromServerCache() {
                #if DEBUG
                Self.navDebugLogger.debug("🔍 [NavDebug] load() 서버 캐시 경로로 완료 matchId=\(self.match.id)")
                #endif
                return
            }
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let detail = try await esportsService.fetchEventDetails(matchId: match.id)
            eventDetail = detail
            isLoading = false  // eventDetail 확보 즉시 화면 표시, 게임 윈도우는 백그라운드 로딩

            let liveStats = liveStatsService
            let matchStartTime = match.startTime
            let playableGames = detail.games.filter { $0.state.isPlayable }

            let cache = GameWindowCache.shared
            await withTaskGroup(of: (String, GameWindow?).self) { group in
                for game in playableGames {
                    let gameId = game.gameId
                    let gameNumber = game.number
                    let isCompleted = game.state == .completed
                    group.addTask {
                        if isCompleted, let cached = await cache.window(for: gameId) {
                            return (gameId, cached)
                        }
                        if let window = try? await liveStats.fetchGameWindow(gameId: gameId, startingTime: nil),
                           !isCompleted || window.hasLiveStats {
                            if isCompleted { await cache.save(window) }
                            return (gameId, window)
                        }
                        guard isCompleted else { return (gameId, nil) }

                        let slotMin = 70.0
                        let broadcastDelay = 20.0
                        let base = broadcastDelay + Double(gameNumber - 1) * slotMin
                        let offsets: [Double] = [55, 45, 35, 20]
                        return await withTaskGroup(of: (Double, GameWindow?).self) { inner in
                            for extra in offsets {
                                let time = matchStartTime.addingTimeInterval((base + extra) * 60.0)
                                inner.addTask {
                                    let w = try? await liveStats.fetchGameWindow(gameId: gameId, startingTime: time)
                                    return (base + extra, w?.hasLiveStats == true ? w : nil)
                                }
                            }
                            var best: (Double, GameWindow)? = nil
                            for await (key, window) in inner {
                                if let window, best == nil || key > best!.0 {
                                    best = (key, window)
                                }
                            }
                            if let w = best?.1 { await cache.save(w) }
                            return (gameId, best?.1)
                        }
                    }
                }
                for await (gameId, window) in group {
                    if let window { gameWindows[gameId] = window }
                }
            }

            if let lastPlayable = detail.games.last(where: { $0.state.isPlayable }) {
                selectedGameId = lastPlayable.gameId
            }

            await loadKillTimelines(for: playableGames, liveStats: liveStats)

            // 완료 경기는 디스크에 저장 (다음 진입 시 즉시 표시)
            // Riot API가 아직 안 채워진 상태(밴픽/승자 없음)면 캐싱하지 않는다 —
            // 여기서 캐싱해버리면 나중에 Riot이 채워줘도 30일 동안 빈 상태로 고정된다.
            if match.state == .completed && Self.isGenuinelyComplete(detail) {
                AppDiskCache.set(.eventDetail(matchId: match.id), value: detail)
            }

            await fetchGameBans(for: playableGames.filter { $0.state == .completed })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 백필 경기(match.games)를 Riot API 없이 그대로 화면 모델로 변환한다. 밴 데이터는 원본에 없어
    /// 항상 빈 배열 — 밴 카드는 자연히 표시 안 됨. games가 없으면(구버전 백필) 스코어만 표시.
    private func loadFromBackfilledGames() {
        guard let games = match.games, !games.isEmpty else { return }

        eventDetail = EventDetailInfo(
            strategyCount: games.count,
            games: games.map {
                GameInfo(number: $0.number, gameId: $0.gameId, state: .completed,
                         blueTeamId: $0.blueTeamId, redTeamId: $0.redTeamId,
                         blueBans: [], redBans: [], winnerTeamId: $0.winnerTeamId)
            },
            teamAEsportsId: match.teamA.id,
            teamBEsportsId: match.teamB.id
        )

        for g in games {
            gameWindows[g.gameId] = GameWindow(
                gameId: g.gameId, gameState: "completed",
                blueTeamId: g.blueTeamId, redTeamId: g.redTeamId,
                bluePlayers: g.bluePlayers, redPlayers: g.redPlayers,
                blueTeamStats: g.blueTeamStats, redTeamStats: g.redTeamStats,
                gameTime: nil, lastFrameTimestamp: nil
            )
        }

        selectedGameId = games.last?.gameId
    }

    // MARK: - Static Preload

    /// 화면 진입 시 미리 로드할 완료 경기 개수 — TodayViewModel/LeagueDetailViewModel/
    /// TournamentDetailViewModel/AppPreloadService가 전부 이 값을 참조한다.
    static let preloadCount = 8

    /// 과거 시즌 백필 데이터(Leaguepedia/datalisk.io 경유)로 생성된 매치 ID인지 판별.
    /// 이런 매치는 Riot esports API가 알지 못하는 ID라 상세 조회를 시도하면 항상 실패한다.
    nonisolated static func isBackfilledMatchId(_ id: String) -> Bool {
        id.hasPrefix("oe_") || id.hasPrefix("lp_")
    }

    /// completed로 표시된 경기인데 Riot의 상세 API(getEventDetails)는 아직 안 채워진 경우
    /// (밴픽·승자 정보 없음)를 구분한다. 이런 "덜 채워진" 응답을 30일 캐시에 그대로 저장하면,
    /// 나중에 Riot이 채워줘도 캐시가 만료될 때까지 계속 빈 상태로 보이게 된다 — 실제로 겪은 버그.
    /// 여러 세트 중 하나라도 완료+승자 확정이면 "충분히 채워졌다"고 본다.
    nonisolated static func isGenuinelyComplete(_ detail: EventDetailInfo) -> Bool {
        detail.games.contains { $0.state == .completed && $0.winnerTeamId != nil }
    }
}
