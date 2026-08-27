//
//  OracleElixirService+LiveReconcile.swift
//  LOLIVE
//
//  Riot 라이브 스탯 피드가 멈춘(stuck) 것으로 판단된 경기를 OE 데이터로 보정한다.
//

import Foundation

extension OracleElixirService {

    private struct SingleMatchStateRow: Decodable {
        let team1Code: String?
        let team2Code: String?
        let team1Wins: String?
        let team2Wins: String?
        let state: String?
    }

    /// Riot 라이브 스탯 피드가 멈춘 것으로 판단된 경기를 OE `/matches/singleMatch/{match.id}`로
    /// 대조한다(Riot 매치 id를 OE가 그대로 쓰는 걸 실측 확인 — 밴 마이그레이션과 같은 경로,
    /// 팀명 퍼지매칭 불필요). 팀 코드가 정확히 대조되지 않으면(리그 미지원 등) nil — 호출부가
    /// Leaguepedia로 폴백한다. **주의**: OE가 "진행 중" 경기를 어떤 state 문자열로 표기하는지는
    /// 아직 실측 못 했음(테스트 시점에 라이브 경기가 없었음) — `completed`가 아니면서 스코어가
    /// 0보다 크면 진행중으로 보수적으로 처리한다. 다음 라이브 경기 때 실제 값 확인 필요.
    ///
    /// 진행 중인 경기라 캐싱하지 않고 매번 새로 조회한다.
    func reconcileStuckLiveMatch(_ match: Match) async -> Match? {
        guard let rows: [SingleMatchStateRow] = await fetch("/matches/singleMatch/\(match.id)"),
              let row = rows.first,
              let team1Code = row.team1Code, let team2Code = row.team2Code,
              let wins1 = Int(row.team1Wins ?? ""), let wins2 = Int(row.team2Wins ?? "")
        else { return nil }

        let teamACode = match.teamA.code.uppercased()
        let teamBCode = match.teamB.code.uppercased()
        let sameOrder: Bool
        if team1Code.uppercased() == teamACode && team2Code.uppercased() == teamBCode {
            sameOrder = true
        } else if team1Code.uppercased() == teamBCode && team2Code.uppercased() == teamACode {
            sameOrder = false
        } else {
            return nil
        }

        let scoreA = sameOrder ? wins1 : wins2
        let scoreB = sameOrder ? wins2 : wins1

        let state: MatchState
        if row.state == "completed" {
            state = .completed
        } else if scoreA > 0 || scoreB > 0 {
            state = .inProgress
        } else {
            return nil
        }

        return Match(id: match.id, league: match.league, teamA: match.teamA, teamB: match.teamB,
                     scoreA: scoreA, scoreB: scoreB, startTime: match.startTime,
                     state: state, blockName: match.blockName)
    }
}
