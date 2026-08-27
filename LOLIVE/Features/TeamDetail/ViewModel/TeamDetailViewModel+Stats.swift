//
//  TeamDetailViewModel+Stats.swift
//  LOLIVE
//
//  팀 "스탯" 탭 — Oracle's Elixir 팀 단위 시즌 집계와 시즌(구간) 전환.
//  선수단/최근경기와는 별도 소스라 실패해도 그쪽엔 영향이 없다.
//

import Foundation

extension TeamDetailViewModel {

    /// 팀 단위 시즌 스탯(Oracle's Elixir) — 선수단/최근경기와 별도 소스라 실패해도 그쪽엔
    /// 영향 없음. "스탯" 탭에서만 쓰이므로 실패하면 그 탭만 빈 상태로 보임.
    /// tournamentId를 안 주면(최초 로드) 현재 시즌 목록도 같이 채우고 최신 시즌을 쓴다.
    func loadTeamStats(tournamentId: String? = nil) async {
        isLoadingTeamStats = true
        defer { isLoadingTeamStats = false }
        if availableSeasons.isEmpty {
            availableSeasons = await OracleElixirService.shared.availableSeasons(league: league)
        }
        teamStats = await OracleElixirService.shared.fetchTeamStats(team: team, league: league, tournamentId: tournamentId)
        selectedSeasonId = tournamentId ?? availableSeasons.first?.id
    }

    /// 스탯 탭의 시즌 칩을 탭했을 때 호출 — 해당 시즌 데이터로 다시 불러온다.
    func selectSeason(_ tournamentId: String) {
        guard tournamentId != selectedSeasonId else { return }
        Task { await loadTeamStats(tournamentId: tournamentId) }
    }
}
