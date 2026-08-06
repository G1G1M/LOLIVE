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
    ///
    /// LCK 등 일부 리그는 스플릿 단위로 리셋되지 않고 "레전드/라이즈 그룹" 같은 시즌 전체 누적
    /// 순위표를 쓴다(Leaguepedia에 공개된 실제 순위표 기준 — HLE 15승4패처럼 한 스플릿 경기 수를
    /// 훨씬 넘는 누적 기록). 그래서 `schedule`(반드시 `fetchAllSchedule`로 시즌 전체를 가져온 것)에서
    /// `seasonStartDate` 이후의 완료 경기를 전부 합산한다 — 특정 스플릿 하나로 좁히면(과거에 시도했던
    /// 방식) 오히려 시즌 누적 기록과 안 맞게 된다. 상대적으로 그룹(레전드/라이즈)은 현재 시즌
    /// `standings`(Riot가 최신 스플릿에서 배정한 그룹)를 그대로 따른다.
    static func reconciled(_ standings: [Standing], schedule: [Match], seasonStartDate: Date) -> [Standing] {
        // 스플릿 누적 순위(레전드/라이즈 그룹 등)에 직전 스플릿의 "Knockouts"(플레이오프) 라운드
        // 경기까지 합산되고 있던 버그 — 실측 대조로 확인함(2026-08 LCK: 이 라운드를 빼야 네이버
        // e스포츠 공식 순위표의 승패/GD와 팀별로 정확히 일치함, 포함하면 HLE가 T1을 근소하게
        // 앞서는 걸로 잘못 계산됨). 플레이오프는 토너먼트 대진이라 라운드로빈처럼 전 팀이 서로
        // 겨루는 구조가 아니라서 애초에 누적 순위표 집계 대상이 아니다.
        let completed = schedule.filter {
            $0.state == .completed && $0.startTime >= seasonStartDate && !Standing.isPlayoffBlock($0.blockName)
        }
        guard !standings.isEmpty, !completed.isEmpty else {
            return standings.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.wins != $1.wins { return $0.wins > $1.wins }
                if $0.losses != $1.losses { return $0.losses < $1.losses }
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
                if $0.losses != $1.losses { return $0.losses < $1.losses }
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
            if $0.losses != $1.losses { return $0.losses < $1.losses }
            return $0.team.name < $1.team.name
        }
    }

    /// LeagueDetailViewModel.isBracketAvailable과 비슷한 키워드 기준이지만, 앱이 Riot API를
    /// `hl=ko-KR`로 호출해서 실제 blockName은 영어가 아니라 한글로 온다(실측: "토너먼트 스테이지",
    /// "플레이오프", "결승", "플레이-인", "대표 선발전" 등 — "final"/"playoff" 같은 영어 키워드는
    /// 하나도 안 걸려서 이 함수가 사실상 죽어있었다). 정규시즌 블록은 전부 "N주 차" 패턴이라
    /// 그 외는 라운드로빈이 아닌 대진표 방식이라고 보고 제외한다. 영어 키워드도 혹시 몰라 남겨둠.
    fileprivate static func isPlayoffBlock(_ blockName: String?) -> Bool {
        guard let raw = blockName, let b = blockName?.lowercased() else { return false }
        let englishKeywords = ["final", "semi", "quarter", "playoff", "knockout", "bracket", "elimination"]
        let koreanKeywords = ["결승", "준결승", "플레이오프", "플레이-인", "토너먼트 스테이지", "8강", "4강", "선발전"]
        if englishKeywords.contains(where: b.contains) { return true }
        if koreanKeywords.contains(where: raw.contains) { return true }
        return false
    }
}
