//
//  MatchDetailViewModel+Polling.swift
//  LOLIVE
//
//  진행 중인 경기의 실시간 폴링. 완료 경기에서는 아예 시작하지 않는다.
//

import Foundation

extension MatchDetailViewModel {

    // MARK: - 폴링 주기

    /// 게임이 실제로 진행 중일 때 — 골드·킬이 초 단위로 바뀌는 구간.
    nonisolated static let livePollInterval: Duration = .seconds(5)
    /// 아직 시작 전일 때. 여기서 볼 건 "드래프트가 열렸는지 / 게임이 시작됐는지"뿐이라
    /// 5초까지 촘촘할 이유가 없다.
    ///
    /// [왜 필요한가] 예전엔 완료 경기만 제외하고 전부 5초였다. 내일 경기 상세를 열어두면
    /// 바뀔 수 있는 값이 하나도 없는데도 `getEventDetails`를 5분에 60번 부른다
    /// (이 엔드포인트는 캐시도 안 탄다).
    nonisolated static let waitingPollInterval: Duration = .seconds(30)

    nonisolated static func pollInterval(hasLiveGame: Bool) -> Duration {
        hasLiveGame ? livePollInterval : waitingPollInterval
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
                let hasLiveGame = eventDetail?.games.contains { $0.state == .inProgress } ?? false
                try? await Task.sleep(for: Self.pollInterval(hasLiveGame: hasLiveGame))
                guard !Task.isCancelled else { break }

                lastPolledAt = Date()

                // eventDetail 폴링: 드래프트 밴픽 + 게임 상태 변화 감지
                if let freshDetail = try? await esports.fetchEventDetails(matchId: matchId) {
                    // 네트워크 응답을 기다리는 동안 stopPolling()으로 취소됐을 수 있다(예: 사용자가
                    // 화면을 벗어남) — 이 경우 응답이 뒤늦게 와도 상태를 건드리면 안 된다. 특히
                    // 뒤로가기 전환 애니메이션 도중에 이 상태 갱신이 겹치면 ScrollView가 다시
                    // 그려지며 맨 위로 튀는 것처럼 보이는 문제가 있었다(실측 확인).
                    guard !Task.isCancelled else { break }

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

                guard !Task.isCancelled else { break }

                // 인게임 스탯: inProgress 게임만 window 요청
                guard let game = eventDetail?.games.first(where: { $0.state == .inProgress }) else { continue }
                // startingTime 을 비우면 게임 "시작" 프레임이 온다 — 진행 중인 경기에서 그러면
                // 5초마다 폴링해도 골드 0·킬 0 이 계속 돌아온다(실측으로 확인한 버그).
                // 피드가 내주는 가장 최신 시점을 명시해야 실제 라이브 값이 온다.
                if let window = try? await liveStats.fetchGameWindow(gameId: game.gameId,
                                                                     startingTime: LiveStatsService.liveEdge()) {
                    guard !Task.isCancelled else { break }
                    gameWindows[game.gameId] = window
                    currentGameTime = await elapsedSeconds(for: game.gameId, window: window)
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
