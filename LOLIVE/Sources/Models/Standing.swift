//
//  Standing.swift
//  LOLIVE
//

import Foundation

struct Standing: Codable, Identifiable, Hashable {
    var id: String { team.id }
    let team: Team
    let wins: Int
    let losses: Int
    let rank: Int
    let winRate: Double
    var gameWins: Int = 0
    var gameLosses: Int = 0
    var gameDiff: Int { gameWins - gameLosses }
    var group: String? = nil
}

extension Standing {
    /// 완료된 경기 스코어로 세트 득실(GD)과 승패를 직접 계산해서 순위를 보정한다.
    ///
    /// Riot의 순위 API(`getStandings`)는 팀별로 결과 반영 시점이 어긋날 수 있다 — 실제로 같은
    /// 경기인데 한쪽 팀 기록만 갱신되고 반대쪽은 안 된 사례를 확인했다(T1 1승1패인데 상대 Gen.G는
    /// 0승1패만 반영, 총 경기 수 자체가 안 맞음). 그래서 Riot이 내려주는 wins/losses를 그대로
    /// 믿지 않고, 완료된 경기 스코어에서 직접 집계한 값을 항상 우선한다. 완료된 경기가 하나도
    /// 없으면(시즌 시작 전 등) 재계산할 근거가 없으므로 Riot 원본 순위를 그대로 사용한다.
    static func reconciled(_ standings: [Standing], schedule: [Match]) -> [Standing] {
        let completed = schedule.filter { $0.state == .completed }
        guard !standings.isEmpty, !completed.isEmpty else {
            return standings.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.wins != $1.wins { return $0.wins > $1.wins }
                if $0.gameDiff != $1.gameDiff { return $0.gameDiff > $1.gameDiff }
                return $0.team.name < $1.team.name
            }
        }

        var gameWins: [String: Int] = [:]
        var gameLosses: [String: Int] = [:]
        var wins: [String: Int] = [:]
        var losses: [String: Int] = [:]
        for match in completed {
            let aCode = match.teamA.code.uppercased()
            let bCode = match.teamB.code.uppercased()
            gameWins[aCode, default: 0] += match.scoreA
            gameLosses[aCode, default: 0] += match.scoreB
            gameWins[bCode, default: 0] += match.scoreB
            gameLosses[bCode, default: 0] += match.scoreA
            if match.scoreA > match.scoreB {
                wins[aCode, default: 0] += 1
                losses[bCode, default: 0] += 1
            } else if match.scoreB > match.scoreA {
                wins[bCode, default: 0] += 1
                losses[aCode, default: 0] += 1
            }
        }

        let recomputed = standings.map { s -> Standing in
            let code = s.team.code.uppercased()
            let w = wins[code] ?? 0
            let l = losses[code] ?? 0
            let total = w + l
            return Standing(team: s.team, wins: w, losses: l, rank: s.rank,
                             winRate: total > 0 ? Double(w) / Double(total) : 0,
                             gameWins: gameWins[code] ?? 0, gameLosses: gameLosses[code] ?? 0,
                             group: s.group)
        }

        let groups = Dictionary(grouping: recomputed, by: { $0.group })
        var reranked: [Standing] = []
        for (_, group) in groups {
            let sorted = group.sorted {
                if $0.wins != $1.wins { return $0.wins > $1.wins }
                if $0.gameDiff != $1.gameDiff { return $0.gameDiff > $1.gameDiff }
                return $0.team.name < $1.team.name
            }
            for (idx, s) in sorted.enumerated() {
                reranked.append(Standing(team: s.team, wins: s.wins, losses: s.losses, rank: idx + 1,
                                          winRate: s.winRate, gameWins: s.gameWins,
                                          gameLosses: s.gameLosses, group: s.group))
            }
        }
        return reranked.sorted {
            if $0.group != $1.group { return ($0.group ?? "") < ($1.group ?? "") }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            return $0.team.name < $1.team.name
        }
    }
}
