//
//  PlayerLiveDetailViewModel.swift
//  LOLIVE
//
//  경기 상세 → 선수 상세에서 보여주는 "세트별 대결 구도"의 상태.
//
//  세트마다 별도 요청이 필요해서(피드가 gameId 단위로만 응답한다) 화면에 들어오자마자
//  전부 받지 않고, 선택된 세트만 받아 캐싱한다. 이미 받은 세트를 다시 고르면 요청이 없다.
//

import Foundation
import Observation
import os

@MainActor
@Observable
final class PlayerLiveDetailViewModel {

    enum LoadFailure {
        /// 이 세트엔 애초에 보여줄 데이터가 없다(아직 시작 안 함, 피드에 이 선수 없음 등).
        case noData
        /// 요청은 했는데 실패했다. 화면에서 감추지 않고 재시도를 열어준다.
        case fetchFailed
    }

    private(set) var matchups: [String: LaneMatchup] = [:]
    private(set) var loadingGameIds: Set<String> = []
    private(set) var failures: [String: LoadFailure] = [:]
    var selectedGameId: String?

    /// 이 화면이 다루는 세트 — 실제로 플레이된 것만, 세트 번호 순.
    private(set) var games: [GameInfo] = []

    private let summonerName: String
    private let gameWindows: [String: GameWindow]
    private let liveStats: LiveStatsServiceProtocol
    private let logger = Logger(subsystem: "com.lolive", category: "PlayerLiveDetail")

    init(summonerName: String,
         games: [GameInfo],
         gameWindows: [String: GameWindow],
         liveStats: LiveStatsServiceProtocol = LiveStatsService()) {
        self.summonerName = summonerName
        self.gameWindows = gameWindows
        self.liveStats = liveStats
        // window가 없는 세트는 대결 구도를 만들 수 없으니 아예 탭에서 뺀다 —
        // 눌러도 아무것도 안 나오는 탭을 보여주지 않기 위함.
        self.games = games
            .filter { $0.state.isPlayable && gameWindows[$0.gameId] != nil }
            .sorted { $0.number < $1.number }
        self.selectedGameId = Self.defaultSelection(games: self.games, windows: gameWindows)?.gameId
    }

    /// 처음 펼쳐 보여줄 세트 — 스탯이 실제로 들어온 세트 중 마지막.
    /// 그냥 마지막 세트를 고르면 방금 시작한 진행 중인 세트(레벨 1·아이템 0개)가 잡힌다.
    static func defaultSelection(games: [GameInfo], windows: [String: GameWindow]) -> GameInfo? {
        games.last { windows[$0.gameId]?.hasLiveStats == true } ?? games.last
    }

    var selectedMatchup: LaneMatchup? {
        selectedGameId.flatMap { matchups[$0] }
    }

    var isLoadingSelected: Bool {
        selectedGameId.map { loadingGameIds.contains($0) } ?? false
    }

    var selectedFailure: LoadFailure? {
        selectedGameId.flatMap { failures[$0] }
    }

    func select(_ gameId: String) {
        selectedGameId = gameId
        Task { await loadSelected() }
    }

    /// 선택된 세트를 받아온다. 이미 있거나 받는 중이면 아무것도 하지 않는다.
    func loadSelected() async {
        guard let gameId = selectedGameId,
              matchups[gameId] == nil,
              !loadingGameIds.contains(gameId),
              let game = games.first(where: { $0.gameId == gameId }),
              let window = gameWindows[gameId]
        else { return }

        guard let capturedAt = window.lastFrameTimestamp else {
            failures[gameId] = .noData
            logger.debug("세트 \(game.number) 생략 — 프레임 시각 없음")
            return
        }

        loadingGameIds.insert(gameId)
        failures[gameId] = nil
        defer { loadingGameIds.remove(gameId) }

        do {
            let detail = try await liveStats.fetchPlayerDetails(gameId: gameId, startingTime: capturedAt)
            if let matchup = LaneMatchup.build(gameNumber: game.number,
                                               window: window,
                                               detail: detail,
                                               summonerName: summonerName) {
                matchups[gameId] = matchup
            } else {
                failures[gameId] = .noData
                logger.debug("세트 \(game.number) 대결 구도 생성 실패 — 피드에 \(self.summonerName) 없음")
            }
        } catch {
            failures[gameId] = .fetchFailed
            logger.debug("세트 \(game.number) 조회 실패: \(String(describing: error))")
        }
    }

    func retrySelected() async {
        if let gameId = selectedGameId { failures[gameId] = nil }
        await loadSelected()
    }
}
