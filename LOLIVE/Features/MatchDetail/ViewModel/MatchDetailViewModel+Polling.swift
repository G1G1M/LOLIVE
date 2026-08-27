//
//  MatchDetailViewModel+Polling.swift
//  LOLIVE
//
//  진행 중인 경기의 실시간 폴링. 완료 경기에서는 아예 시작하지 않는다.
//

import Foundation

extension MatchDetailViewModel {

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
                if let window = try? await liveStats.fetchGameWindow(gameId: game.gameId, startingTime: nil) {
                    guard !Task.isCancelled else { break }
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
