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

    // MARK: - Private

    private let match: Match
    private let esportsService: RiotEsportsServiceProtocol
    private let liveStatsService: LiveStatsServiceProtocol
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
                        // 완료 게임은 디스크 캐시 우선 조회
                        if isCompleted, let cached = await cache.window(for: gameId) {
                            return (gameId, cached)
                        }

                        // 먼저 startingTime 없이 시도
                        if let window = try? await liveStats.fetchGameWindow(gameId: gameId, startingTime: nil),
                           !isCompleted || window.hasLiveStats {
                            if isCompleted { await cache.save(window) }
                            return (gameId, window)
                        }
                        guard isCompleted else { return (gameId, nil) }

                        // 완료 게임: 게임 번호 기반으로 예상 종료 시점 탐색
                        // 게임 슬롯: 방송 준비(~20분) + 평균 게임(~50분) = 약 70분/게임
                        let slotMin = 70.0
                        let broadcastDelay = 20.0
                        let base = broadcastDelay + Double(gameNumber - 1) * slotMin
                        // base 기준 +20~+55분 범위에서 높은 값부터 탐색 (최후 프레임에 근접)
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
                    if let window {
                        gameWindows[gameId] = window
                    }
                }
            }

            // 가장 최근 플레이된 게임을 기본 선택
            if let lastPlayable = detail.games.last(where: { $0.state.isPlayable }) {
                selectedGameId = lastPlayable.gameId
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

                // eventDetail 재조회: 세트 전환(Game1 종료 → Game2 시작) 감지
                if let freshDetail = try? await esports.fetchEventDetails(matchId: matchId) {
                    // 새로운 in-progress 게임이 생기면 자동으로 해당 게임으로 전환
                    let prevLiveGameId = eventDetail?.games.first(where: { $0.state == .inProgress })?.gameId
                    let newLiveGame = freshDetail.games.first(where: { $0.state == .inProgress })
                    if let newGame = newLiveGame, newGame.gameId != prevLiveGameId {
                        selectedGameId = newGame.gameId
                    }
                    eventDetail = freshDetail
                }

                // 현재 in-progress 게임의 실시간 통계 + 인게임 시간 업데이트
                guard let game = eventDetail?.games.first(where: { $0.state == .inProgress }) else { continue }
                if let window = try? await liveStats.fetchGameWindow(gameId: game.gameId, startingTime: nil) {
                    gameWindows[game.gameId] = window
                    // window에 gameTime이 있으면 사용, 없으면 details API로 fallback
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
