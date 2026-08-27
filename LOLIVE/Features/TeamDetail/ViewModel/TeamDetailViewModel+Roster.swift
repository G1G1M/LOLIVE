//
//  TeamDetailViewModel+Roster.swift
//  LOLIVE
//
//  "현재 주전" 역산 — Riot getTeams 로스터엔 주전/후보 구분이 없어서,
//  최근 완료 경기의 실제 출전 명단과 대조해 뽑아낸다.
//

import Foundation
import os

extension TeamDetailViewModel {

    /// 최근 완료 경기의 마지막 게임 참가자 명단으로 "현재 주전"을 역산한다. 방금 끝난 경기는
    /// 시리즈 상태(`match.state`)만 completed로 먼저 반영되고 게임별 상세(`getEventDetails`의
    /// `games[].state`)는 Riot이 뒤늦게 채워주는 지연이 실제로 있어서(실측: LPL AL 팀에서
    /// 최신 경기가 games 전부 unstarted로 남아있는 채로 발견함), 가장 최근 경기 하나만 보면
    /// 주전 판별이 종종 실패한다. 성공할 때까지 최근 5경기까지 순서대로 시도한다.
    func loadCurrentStarters() async {
        for match in recentMatches.prefix(5) {
            #if DEBUG
            Self.teamDetailLogger.debug("[Starters] \(self.team.code) 시도: \(match.startTime) vs \(match.teamA.code == self.team.code ? match.teamB.code : match.teamA.code) matchId=\(match.id)")
            #endif
            guard let detail = try? await service.fetchEventDetails(matchId: match.id),
                  let lastGame = detail.games.last(where: { $0.state == .completed })
            else {
                #if DEBUG
                Self.teamDetailLogger.debug("[Starters] \(self.team.code) eventDetails/lastGame 실패")
                #endif
                continue
            }

            let isTeamA = match.teamA.id == team.id || match.teamA.code == team.code
            let myEsportsId = isTeamA ? detail.teamAEsportsId : detail.teamBEsportsId
            guard let window = try? await liveStatsService.fetchGameWindow(gameId: lastGame.gameId, startingTime: nil)
            else {
                #if DEBUG
                Self.teamDetailLogger.debug("[Starters] \(self.team.code) gameId=\(lastGame.gameId) window 실패")
                #endif
                continue
            }

            // blue/red 배정은 반드시 window 자기 자신의 blueTeamId/redTeamId로 판단해야 한다 —
            // getEventDetails(lastGame)와 LiveStats(window)가 같은 게임인데도 서로 다른 blue/red
            // 배정을 준 사례를 실측으로 확인함(LPL JDG: lastGame은 LGD=blue/JDG=red라는데 window는
            // JDG=blue/LGD=red). lastGame 기준으로 판단하면 window에서 상대팀 선수를 골라오게 된다.
            let myPlayers = window.blueTeamId == myEsportsId ? window.bluePlayers : window.redPlayers
            guard !myPlayers.isEmpty else {
                #if DEBUG
                Self.teamDetailLogger.debug("[Starters] \(self.team.code) myEsportsId=\(myEsportsId) blueId=\(window.blueTeamId) redId=\(window.redTeamId) — 양쪽 다 매칭 안 됨")
                #endif
                continue
            }

            let matched = matchAgainstRoster(myPlayers)
            #if DEBUG
            Self.teamDetailLogger.debug("[Starters] \(self.team.code) window선수=\(myPlayers.map(\.summonerName)) 로스터매칭=\(matched.count)명 \(Array(matched))")
            #endif
            // 매칭이 0명이면 blue/red 판정이 실제로 틀렸거나(다른 팀 명단을 받아온 경우) 게임
            // 상세가 아직 안 채워진 것 — 다음 최근 경기로 재시도(이 for 루프가 이미 그 역할).
            guard !matched.isEmpty else { continue }
            currentStarterNames = matched
            return
        }
        #if DEBUG
        Self.teamDetailLogger.debug("[Starters] \(self.team.code) 5경기 전부 실패 — currentStarterNames 비어있음")
        #endif
    }

    /// LiveStats API의 소환사명 표기가 리그마다 다르다(실측 확인) — LCK는 "T1 Oner"처럼 팀 코드
    /// 뒤에 공백을 두지만, LPL은 "BLGKnight"처럼 공백 없이 그대로 붙인다. 특정 구분자를 가정하고
    /// 접두사를 "제거"하려 하면 리그마다 깨지므로, 대신 이미 알고 있는 로스터 소환사명이 window
    /// 이름의 **접미사**로 포함되는지를 직접 검사한다 — 구분자 형식과 무관하게 안전하다.
    private func matchAgainstRoster(_ windowPlayers: [PlayerStats]) -> Set<String> {
        let windowNames = windowPlayers.map {
            $0.summonerName.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "")
        }
        var result: Set<String> = []
        for player in players {
            let rosterName = player.summonerName.trimmingCharacters(in: .whitespaces).lowercased()
            let rosterNameNoSpace = rosterName.replacingOccurrences(of: " ", with: "")
            guard !rosterNameNoSpace.isEmpty else { continue }
            if windowNames.contains(where: { $0 == rosterNameNoSpace || $0.hasSuffix(rosterNameNoSpace) }) {
                result.insert(rosterName)
            }
        }
        return result
    }
}
