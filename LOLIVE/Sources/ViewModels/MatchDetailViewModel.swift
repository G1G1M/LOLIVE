//
//  MatchDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class MatchDetailViewModel {

    // MARK: - Properties

    var eventDetail: EventDetailInfo? = nil
    var gameWindows: [String: GameWindow] = [:]
    var leaguepediaBans: [String: (team1Bans: [String], team2Bans: [String])] = [:]
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

    /// Riot API 밴 데이터가 없을 경우 Leaguepedia 데이터로 fallback.
    /// blueTeamId/redTeamId + teamAEsportsId를 이용해 team1/team2 → blue/red 매핑.
    func correctedBans(for game: GameInfo) -> (blue: [String], red: [String]) {
        if !game.blueBans.isEmpty || !game.redBans.isEmpty {
            return (game.blueBans, game.redBans)
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

    private let match: Match
    private let esportsService: RiotEsportsServiceProtocol
    private let liveStatsService: LiveStatsServiceProtocol
    private let leaguepediaService = LeaguepediaService()
    private var pollingTask: Task<Void, Never>?

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
            if await tryLoadFromCache() { return }
            if await tryLoadFromServerCache() { return }
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
                AppDiskCache.set(key: "event_detail_v2_\(match.id)", value: detail)
            }

            await fetchLeaguepediaBans(for: playableGames.filter { $0.state == .completed })
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
    private nonisolated static func isGenuinelyComplete(_ detail: EventDetailInfo) -> Bool {
        detail.games.contains { $0.state == .completed && $0.winnerTeamId != nil }
    }

    /// 경기 목록 화면에서 완료된 경기 데이터를 백그라운드로 미리 캐싱.
    /// 이미 캐시된 경기는 건너뜀.
    static func preload(match: Match) {
        guard match.state == .completed, !isBackfilledMatchId(match.id) else { return }
        let detailKey = "event_detail_v2_\(match.id)"
        guard (AppDiskCache.get(key: detailKey, maxAge: 30 * 24 * 3600) as EventDetailInfo?) == nil else { return }

        Task.detached(priority: .background) {
            let esports = RiotEsportsService()
            let liveStats = LiveStatsService()

            let detail: EventDetailInfo
            if let serverDetail = await FirebaseMatchDetailService.fetchCachedDetail(matchId: match.id),
               isGenuinelyComplete(serverDetail) {
                detail = serverDetail
            } else if let riotDetail = try? await esports.fetchEventDetails(matchId: match.id),
                      isGenuinelyComplete(riotDetail) {
                // 아직 안 채워진 상태면 캐싱 안 하고 넘어감 — 다음 preload 시도(스케줄 새로고침마다)에
                // 다시 확인해서, Riot/서버가 채워주는 대로 자연스럽게 잡히게 한다.
                detail = riotDetail
            } else {
                return
            }
            AppDiskCache.set(key: detailKey, value: detail)

            let cache = GameWindowCache.shared
            let startTime = match.startTime
            await withTaskGroup(of: Void.self) { group in
                for game in detail.games where game.state == .completed {
                    let gid = game.gameId
                    let num = game.number
                    group.addTask {
                        guard await cache.window(for: gid) == nil else { return }
                        if let w = try? await liveStats.fetchGameWindow(gameId: gid, startingTime: nil),
                           w.hasLiveStats {
                            await cache.save(w); return
                        }
                        let base = 20.0 + Double(num - 1) * 70.0
                        var best: (Double, GameWindow)? = nil
                        await withTaskGroup(of: (Double, GameWindow?).self) { inner in
                            for extra in [55.0, 45.0, 35.0, 20.0] {
                                let t = startTime.addingTimeInterval((base + extra) * 60)
                                inner.addTask {
                                    let w = try? await liveStats.fetchGameWindow(gameId: gid, startingTime: t)
                                    return (base + extra, w?.hasLiveStats == true ? w : nil)
                                }
                            }
                            for await (k, w) in inner {
                                if let w, best == nil || k > best!.0 { best = (k, w) }
                            }
                        }
                        if let w = best?.1 { await cache.save(w) }
                    }
                }
            }
        }
    }

    // MARK: - Cache helpers

    private func tryLoadFromCache() async -> Bool {
        guard let detail: EventDetailInfo = AppDiskCache.get(key: "event_detail_v2_\(match.id)", maxAge: 30 * 24 * 3600),
              Self.isGenuinelyComplete(detail)
        else { return false }

        eventDetail = detail
        selectedGameId = detail.games.last(where: { $0.state.isPlayable })?.gameId

        let cache = GameWindowCache.shared
        for game in detail.games.filter({ $0.state.isPlayable }) {
            if let window = await cache.window(for: game.gameId) {
                gameWindows[game.gameId] = window
            }
        }

        for game in detail.games.filter({ $0.state.isPlayable }) {
            if let cached: [KillEvent] = AppDiskCache.get(
                key: "kill_timeline_\(game.gameId)", maxAge: 30 * 24 * 3600) {
                killTimelines[game.gameId] = cached
            }
        }

        await fetchLeaguepediaBans(for: detail.games.filter { $0.state == .completed })
        return true
    }

    /// 서버(getMatchDetail Callable)에 이 경기의 상세가 이미 캐싱돼 있으면 그걸 디스크에
    /// 저장하고 tryLoadFromCache()로 나머지(게임 윈도우 등)까지 일관되게 로딩한다.
    private func tryLoadFromServerCache() async -> Bool {
        guard let detail = await FirebaseMatchDetailService.fetchCachedDetail(matchId: match.id),
              Self.isGenuinelyComplete(detail)
        else { return false }
        AppDiskCache.set(key: "event_detail_v2_\(match.id)", value: detail)
        return await tryLoadFromCache()
    }

    private func loadKillTimelines(for games: [GameInfo], liveStats: LiveStatsServiceProtocol) async {
        await withTaskGroup(of: (String, [KillEvent]).self) { group in
            for game in games {
                let gameId = game.gameId
                let isCompleted = game.state == .completed
                group.addTask {
                    if isCompleted,
                       let cached: [KillEvent] = AppDiskCache.get(
                           key: "kill_timeline_\(gameId)", maxAge: 30 * 24 * 3600) {
                        return (gameId, cached)
                    }
                    let events = (try? await liveStats.fetchKillTimeline(gameId: gameId)) ?? []
                    if !events.isEmpty && isCompleted {
                        AppDiskCache.set(key: "kill_timeline_\(gameId)", value: events)
                    }
                    return (gameId, events)
                }
            }
            for await (gameId, events) in group {
                if !events.isEmpty { killTimelines[gameId] = events }
            }
        }
    }

    private func fetchLeaguepediaBans(for games: [GameInfo]) async {
        let lpService = leaguepediaService
        await withTaskGroup(of: (String, (team1Bans: [String], team2Bans: [String])?).self) { group in
            for game in games {
                guard game.blueBans.isEmpty && game.redBans.isEmpty else { continue }
                let gameId = game.gameId
                group.addTask {
                    let bans = await lpService.fetchBans(riotGameId: gameId)
                    return (gameId, bans)
                }
            }
            for await (gameId, bans) in group {
                if let bans { self.leaguepediaBans[gameId] = bans }
            }
        }
    }

    func startPolling() {
        // 경기가 예정/진행 중일 때만 폴링 (완료 경기는 폴링 불필요)
        guard match.state != .completed else { return }
        stopPolling()
        let esports = esportsService
        let liveStats = liveStatsService
        let matchId = match.id
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }

                lastPolledAt = Date()

                // eventDetail 폴링: 드래프트 밴픽 + 게임 상태 변화 감지
                if let freshDetail = try? await esports.fetchEventDetails(matchId: matchId) {
                    let prevLiveGameId = eventDetail?.games.first(where: { $0.state == .inProgress })?.gameId
                    let newLiveGame = freshDetail.games.first(where: { $0.state == .inProgress })

                    // 새 게임 시작 감지 → 자동 전환
                    if let newGame = newLiveGame, newGame.gameId != prevLiveGameId {
                        selectedGameId = newGame.gameId
                    }

                    // 드래프트 밴픽 감지: unstarted 게임에 밴 데이터가 생기면 자동 선택
                    if newLiveGame == nil,
                       let draftGame = freshDetail.games.first(where: {
                           $0.state == .unstarted && (!$0.blueBans.isEmpty || !$0.redBans.isEmpty)
                       }),
                       selectedGameId != draftGame.gameId {
                        selectedGameId = draftGame.gameId
                    }

                    eventDetail = freshDetail
                }

                // 인게임 스탯: inProgress 게임만 window 요청
                guard let game = eventDetail?.games.first(where: { $0.state == .inProgress }) else { continue }
                if let window = try? await liveStats.fetchGameWindow(gameId: game.gameId, startingTime: nil) {
                    gameWindows[game.gameId] = window
                    if let t = window.gameTime {
                        currentGameTime = t
                    } else {
                        currentGameTime = try? await liveStats.fetchGameDetails(gameId: game.gameId)
                    }
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

}
