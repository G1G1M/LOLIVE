//
//  LeagueDetailViewModel+History.swift
//  LOLIVE
//
//  리그 상세 "기록" 탭 — 서버(Firestore)에 백필된 과거 시즌 데이터를 연도별로 조회한다.
//  Leaguepedia를 직접 호출하지 않기 때문에 백필이 안 된 리그는 빈 목록으로 온다.
//

import Foundation

extension LeagueDetailViewModel {

    /// 과거 시즌이 존재하는 연도 목록을 서버(Firestore 백필 데이터)에서 조회.
    /// Leaguepedia를 직접 호출하지 않는다 — 백필이 안 된 리그는 빈 목록으로 온다.
    func loadHistoricalYears() async {
        hasAttemptedHistoricalLoad = true
        guard historicalYears.isEmpty,
              let leagueName = LeaguepediaService.shared.leaguepediaName(for: league)
        else { return }
        isLoadingHistoricalYears = true
        defer { isLoadingHistoricalYears = false }

        historicalYears = await FirebaseHistoricalService.fetchYears(leagueName: leagueName)
        if selectedHistoricalYear == nil {
            selectedHistoricalYear = historicalYears.first
        }
        if let year = selectedHistoricalYear {
            await loadHistoricalMatches(year: year)
        }
    }

    func selectHistoricalYear(_ year: Int) {
        guard selectedHistoricalYear != year else { return }
        selectedHistoricalYear = year
        historicalMatches = []
        selectedHistoricalRound = nil
        Task { await loadHistoricalMatches(year: year) }
    }

    var availableHistoricalRounds: [Match.RoundGroup] {
        Match.roundGroups(from: historicalMatches)
    }

    private func loadHistoricalMatches(year: Int) async {
        guard let leagueName = LeaguepediaService.shared.leaguepediaName(for: league) else { return }
        isLoadingHistoricalMatches = true
        defer { isLoadingHistoricalMatches = false }
        let fetched = await FirebaseHistoricalService.fetchMatches(leagueName: leagueName, year: year)
        historicalMatches = Match.deduplicatedAcrossSources(fetched)
            .sorted { $0.startTime < $1.startTime }
    }
}
