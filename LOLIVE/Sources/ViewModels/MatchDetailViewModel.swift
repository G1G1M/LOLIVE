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
    var leaguepediaBans: [String: (team1: [String], team2: [String])] = [:]
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var selectedGameId: String? = nil
    var currentGameTime: Int? = nil   // 인게임 경과 시간 (초)

    // MARK: - Computed

    var selectedGame: GameInfo? {
        guard let detail = eventDetail else { return nil }
        if let selectedGameId {
            return detail.games.first { $0.gameId == selectedGameId }
        }
        return detail.games.first { $0.state.isPlayable }
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
            return (lp.team1, lp.team2)
        } else {
            return (lp.team2, lp.team1)
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

            // Riot API에 밴 데이터가 없으면 Leaguepedia에서 보완
            let lpService = leaguepediaService
            let completedGames = playableGames.filter { $0.state == .completed }
            await withTaskGroup(of: (String, (team1: [String], team2: [String])?).self) { group in
                for game in completedGames {
                    guard game.blueBans.isEmpty && game.redBans.isEmpty else { continue }
                    let gameId = game.gameId
                    group.addTask {
                        let bans = await lpService.fetchBans(riotGameId: gameId)
                        return (gameId, bans)
                    }
                }
                for await (gameId, bans) in group {
                    if let bans { leaguepediaBans[gameId] = bans }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPolling() {
        guard match.state == .inProgress else { return }
        stopPolling()
        let esports = esportsService
        let liveStats = liveStatsService
        let matchId = match.id
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }

                if let freshDetail = try? await esports.fetchEventDetails(matchId: matchId) {
                    let prevLiveGameId = eventDetail?.games.first(where: { $0.state == .inProgress })?.gameId
                    let newLiveGame = freshDetail.games.first(where: { $0.state == .inProgress })
                    if let newGame = newLiveGame, newGame.gameId != prevLiveGameId {
                        selectedGameId = newGame.gameId
                    }
                    eventDetail = freshDetail
                }

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
