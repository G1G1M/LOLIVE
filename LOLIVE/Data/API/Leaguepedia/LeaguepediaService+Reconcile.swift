//
//  LeaguepediaService+Reconcile.swift
//  LOLIVE
//
//  Riot이 결과를 안 채워주는 대회(케스파컵 등)의 스코어·상태를 Leaguepedia로 보완한다.
//  Oracle's Elixir 경로가 먼저 시도되고, 거기서 실패했을 때의 최종 폴백.
//

import Foundation

extension LeaguepediaService {

    // MARK: - Riot 미보고 결과 보완 (케스파컵 등)

    /// 케스파컵처럼 Riot Esports API가 경기 상태/스코어를 갱신해주지 않는 대회를 위해,
    /// 현재 진행 중인 대회의 Leaguepedia 실제 결과를 가져온다.
    /// Worlds/MSI 과거 기록용 30일 캐시와 달리, 진행 중 대회라 15분 TTL로 짧게 캐싱한다.
    func fetchLiveTournamentResults(for league: League) async -> [Match] {
        guard let leagueName = leaguepediaName(for: league) else {
            #if DEBUG
            // reconcileLPLogger.debug("🔎 [Reconcile] leaguepediaName(for: \(league.name)) = nil — 리그명 매핑 실패")
            #endif
            return []
        }
        let pages = await cachedOrFetchPages(leagueName: leagueName)
        guard let currentPage = currentTournamentPage(from: pages) else {
            #if DEBUG
            // reconcileLPLogger.debug("🔎 [Reconcile] \(leagueName) 대회 페이지 목록이 비어있음 (pages.count=\(pages.count))")
            #endif
            return []
        }
        #if DEBUG
        // reconcileLPLogger.debug("🔎 [Reconcile] \(leagueName) 현재 페이지: \(currentPage.page)")
        #endif

        let cacheKey = "lpresults_\(leagueName)_\(currentPage.page)"
        if let cached: [Match] = AppDiskCache.get(key: cacheKey, maxAge: 15 * 60) {
            #if DEBUG
            // reconcileLPLogger.debug("🔎 [Reconcile] \(currentPage.page) 캐시 히트 \(cached.count)건 (15분 이내)")
            #endif
            return cached
        }

        let matches = await matchesForOverviewPage(currentPage.page, league: league)
        #if DEBUG
        // reconcileLPLogger.debug("🔎 [Reconcile] \(currentPage.page) API 조회 \(matches.count)건")
        #endif
        if !matches.isEmpty { AppDiskCache.set(key: cacheKey, value: matches) }
        return matches
    }

    /// pages는 DateStart 내림차순 정렬돼 있음 — 그중 "이미 시작한" 대회 중 가장 최근 것을 고른다.
    /// 정규시즌 도중에도 플레이오프 페이지가 미래 DateStart로 이미 등록돼 있는 경우가 있어서,
    /// 그냥 pages.first(가장 최근 DateStart)를 쓰면 아직 시작도 안 한 플레이오프를 "현재 대회"로
    /// 잘못 고르게 된다 (실제로 겪은 버그 — 그 페이지엔 당연히 경기가 없어서 보정이 항상 실패했음).
    /// 아직 아무 대회도 시작 안 했으면(프리시즌 등) 첫 번째로 폴백한다.
    private func currentTournamentPage(from pages: [LPTournamentEntry]) -> LPTournamentEntry? {
        pages.first(where: { $0.dateStart <= Date() }) ?? pages.first
    }

    /// Riot 경기 목록 중 (1) 시작 시각이 한참 지났는데도 `unstarted`로 멈춰있거나
    /// (2) `completed`인데 스코어가 0:0으로 비어 있는(=Riot이 결과를 안 준) 항목,
    /// (3) `inProgress`인데 90분 넘게 스코어 변화가 없는(=실제론 끝났는데 Riot이 안 따라잡은) 항목을
    /// 같은 팀 조합·비슷한 시각의 Leaguepedia 경기로 매칭해 스코어·상태만 교체한다.
    /// 팀 로고 등 나머지 메타데이터는 Riot 원본을 유지해 화면 표시 일관성을 지킨다.
    func reconcileResults(riotMatches: [Match], leaguepediaMatches: [Match]) -> [Match] {
        guard !leaguepediaMatches.isEmpty else { return riotMatches }
        let unstartedCutoff = Date().addingTimeInterval(-3 * 3600)
        let inProgressCutoff = Date().addingTimeInterval(-90 * 60)

        return riotMatches.map { riot in
            let isStaleUnstarted = riot.state == .unstarted && riot.startTime < unstartedCutoff
            let isZeroScoreCompleted = riot.state == .completed && riot.scoreA == 0 && riot.scoreB == 0
            let isStuckInProgress = riot.state == .inProgress && riot.startTime < inProgressCutoff
            guard isStaleUnstarted || isZeroScoreCompleted || isStuckInProgress else { return riot }
            guard let lp = leaguepediaMatches.first(where: { lp in
                lp.state == .completed &&
                sameTeams(riot, lp) &&
                abs(lp.startTime.timeIntervalSince(riot.startTime)) < 6 * 3600
            }) else {
                #if DEBUG
                // reconcileLPLogger.debug("🔎 [Reconcile] \(riot.teamA.code) vs \(riot.teamB.code) — Leaguepedia \(leaguepediaMatches.count)건 중 매칭되는 completed 경기 없음")
                // for lp in leaguepediaMatches where sameTeams(riot, lp) {
                //     reconcileLPLogger.debug("🔎 [Reconcile]   팀은 일치하나 state=\(lp.state.rawValue) 또는 시간차 큼 (lp.startTime=\(lp.startTime.description))")
                // }
                #endif
                return riot
            }

            let sameOrder = teamsMatch(riot.teamA, lp.teamA)
            let scoreA = sameOrder ? lp.scoreA : lp.scoreB
            let scoreB = sameOrder ? lp.scoreB : lp.scoreA

            return Match(id: riot.id, league: riot.league, teamA: riot.teamA, teamB: riot.teamB,
                         scoreA: scoreA, scoreB: scoreB, startTime: riot.startTime,
                         state: .completed, blockName: riot.blockName)
        }
    }

    /// Riot 라이브 스탯 피드가 멈춘 것으로 판단된 경기를 Leaguepedia와 대조.
    ///
    /// Leaguepedia의 MatchSchedule은 시리즈가 다 안 끝나도 Team1Score/Team2Score를 세트가
    /// 끝날 때마다 갱신해준다 (Winner만 시리즈 전체가 끝나야 채워짐) — 그래서 `.completed`뿐 아니라
    /// `.inProgress`(부분 스코어)도 받아들인다. 시리즈가 끝났으면 `.completed`인 Match를,
    /// 세트만 진행됐으면 `.inProgress`인 Match를 반환한다. 스코어가 전혀 없으면(0-0, 미시작) nil.
    func reconcileStuckLiveMatch(_ match: Match) async -> Match? {
        let lpMatches = await fetchLiveTournamentResults(for: match.league)
        guard let lp = lpMatches.first(where: { lp in
            (lp.state == .completed || lp.state == .inProgress) &&
            sameTeams(match, lp) &&
            abs(lp.startTime.timeIntervalSince(match.startTime)) < 6 * 3600
        }) else { return nil }

        let sameOrder = teamsMatch(match.teamA, lp.teamA)
        let scoreA = sameOrder ? lp.scoreA : lp.scoreB
        let scoreB = sameOrder ? lp.scoreB : lp.scoreA
        #if DEBUG
        // reconcileLPLogger.debug("""
        //     🔁 [Reconcile] stuckLiveMatch \(match.teamA.code) vs \(match.teamB.code) — \
        //     lp.teamA=\(lp.teamA.name) lp.teamB=\(lp.teamB.name) sameOrder=\(sameOrder) \
        //     리보정전(\(match.scoreA)-\(match.scoreB)) → 리보정후(\(scoreA)-\(scoreB))
        //     """)
        #endif
        return Match(id: match.id, league: match.league, teamA: match.teamA, teamB: match.teamB,
                     scoreA: scoreA, scoreB: scoreB, startTime: match.startTime,
                     state: lp.state, blockName: match.blockName)
    }

    private func sameTeams(_ a: Match, _ b: Match) -> Bool {
        (teamsMatch(a.teamA, b.teamA) && teamsMatch(a.teamB, b.teamB)) ||
        (teamsMatch(a.teamA, b.teamB) && teamsMatch(a.teamB, b.teamA))
    }

    /// 이름이 정확히 같거나, 한쪽 이름이 다른 쪽에 포함되거나(예: "FURIA" ⊂ "FURIA ESPORTS"),
    /// Riot 팀 코드가 상대 이름과 겹치면 같은 팀으로 간주한다. Leaguepedia MatchSchedule의
    /// Team1/Team2는 위키 페이지명이라 Riot의 팀명과 완전히 일치하지 않는 경우가 있어 관대하게 비교한다.
    private func teamsMatch(_ a: Team, _ b: Team) -> Bool {
        let nameA = normalizedName(a)
        let nameB = normalizedName(b)
        if nameA == nameB || nameA.contains(nameB) || nameB.contains(nameA) { return true }

        let codeA = a.code.uppercased().trimmingCharacters(in: .whitespaces)
        let codeB = b.code.uppercased().trimmingCharacters(in: .whitespaces)
        if !codeA.isEmpty && (codeA == nameB || nameB.contains(codeA)) { return true }
        if !codeB.isEmpty && (codeB == nameA || nameA.contains(codeB)) { return true }
        return false
    }

    private func normalizedName(_ team: Team) -> String {
        team.name.uppercased().trimmingCharacters(in: .whitespaces)
    }

}
