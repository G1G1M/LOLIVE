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
        // 예정 경기: 게임 데이터 없음 → 즉시 반환 (폴링이 시작 후 자동 감지)
        guard match.state != .unstarted else { return }

        // 완료된 경기: 디스크 캐시 먼저 확인 → 있으면 로딩 없이 즉시 표시
        if match.state == .completed, await tryLoadFromCache() { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let detail = try await esportsService.fetchEventDetails(matchId: match.id)
            eventDetail = detail

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

            // 완료 경기는 디스크에 저장 (다음 진입 시 즉시 표시)
            if match.state == .completed {
                AppDiskCache.set(key: "event_detail_v2_\(match.id)", value: detail)
            }

            await fetchLeaguepediaBans(for: playableGames.filter { $0.state == .completed })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Static Preload

    /// 경기 목록 화면에서 완료된 경기 데이터를 백그라운드로 미리 캐싱.
    /// 이미 캐시된 경기는 건너뜀.
    static func preload(match: Match) {
        guard match.state == .completed else { return }
        let detailKey = "event_detail_v2_\(match.id)"
        guard (AppDiskCache.get(key: detailKey, maxAge: 30 * 24 * 3600) as EventDetailInfo?) == nil else { return }

        Task.detached(priority: .background) {
            let esports = RiotEsportsService()
            let liveStats = LiveStatsService()
            guard let detail = try? await esports.fetchEventDetails(matchId: match.id) else { return }
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
        guard let detail: EventDetailInfo = AppDiskCache.get(key: "event_detail_v2_\(match.id)", maxAge: 30 * 24 * 3600)
        else { return false }

        eventDetail = detail
        selectedGameId = detail.games.last(where: { $0.state.isPlayable })?.gameId

        let cache = GameWindowCache.shared
        for game in detail.games.filter({ $0.state.isPlayable }) {
            if let window = await cache.window(for: game.gameId) {
                gameWindows[game.gameId] = window
            }
        }

        await fetchLeaguepediaBans(for: detail.games.filter { $0.state == .completed })
        return true
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
