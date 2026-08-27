//
//  TeamDetailViewModel+Historical.swift
//  LOLIVE
//
//  백필된 팀/리그 컨텍스트 전용 로딩 경로.
//  합성 ID(oe_/lp_) 경기는 Riot 실시간 API가 모르기 때문에 서버 백필 데이터만 쓴다.
//

import Foundation
import os

extension TeamDetailViewModel {

    /// 백필된 팀/리그 컨텍스트 전용 로딩 경로. `historicalMatches`(서버, getHistoricalYears/
    /// getHistoricalMatches Callable — LeagueDetailView+History와 동일한 데이터)에서 이 팀이
    /// 나온 과거 경기를 찾아 최근경기/상대전적을 채우고, 가장 최근 경기의 게임별 실제 출전
    /// 명단(Match.games, 백필 시점에 이미 저장돼 있음)에서 선수단을 뽑는다 — Riot 실시간 API는
    /// 이 합성 ID를 모르니 호출하지 않는다.
    func loadFromHistoricalData() async {
        let hadCache = preloadFromCache()
        isLoading = !hadCache
        loadFailed = false
        defer { isLoading = false }

        func isThisTeam(_ m: Match) -> Bool {
            m.teamA.id == team.id || m.teamA.code == team.code ||
            m.teamB.id == team.id || m.teamB.code == team.code
        }

        let years = await FirebaseHistoricalService.fetchYears(leagueName: league.name)
        var teamMatches: [Match] = []
        for year in years.sorted(by: >).prefix(3) {
            let matches = await FirebaseHistoricalService.fetchMatches(leagueName: league.name, year: year)
            teamMatches = matches.filter(isThisTeam)
            if !teamMatches.isEmpty { break }
        }

        #if DEBUG
        Self.teamDetailLogger.debug("[TeamDetail] 백필 경로 — league.name=\(self.league.name) years=\(years) 매칭된 경기=\(teamMatches.count)")
        #endif

        guard !teamMatches.isEmpty else {
            if !hadCache { loadFailed = true }
            return
        }

        applyMatches(teamMatches)
        await loadRosterFromHistoricalMatch()
        Task { await loadTeamStats() }
    }

    /// 가장 최근(연도 내 마지막 게임 번호) 백필 경기의 실제 출전 명단으로 선수단을 채운다.
    /// 백필 데이터는 "그 경기에 실제로 뛴 5명"이 확정값이라 현재 라이브 로스터처럼 주전/후보를
    /// 역산할 필요가 없다. 백필 소스(Match.games)엔 선수 이미지 URL이 없어서, Leaguepedia에서
    /// 별도로 조회한다 — 로스터가 그 경기 시점 이후로 안 바뀌는 한 이미지도 그대로라 7일 디스크
    /// 캐시가 재진입마다 그대로 재사용됨(선수당 최초 1회만 실제 네트워크 요청).
    private func loadRosterFromHistoricalMatch() async {
        guard let lastMatch = recentMatches.first,
              let games = lastMatch.games,
              let lastGame = games.max(by: { $0.number < $1.number })
        else { return }

        let myPlayers = lastGame.blueTeamId == team.id ? lastGame.bluePlayers : lastGame.redPlayers
        guard !myPlayers.isEmpty else { return }

        let basePlayers = myPlayers.map {
            Player(id: "\($0.participantId)", summonerName: $0.summonerName, firstName: nil, lastName: nil,
                   role: $0.role, imageURL: nil, teamId: team.id, teamCode: team.code)
        }

        let oracleElixir = OracleElixirService.shared
        let imageURLs: [Int: URL] = await withTaskGroup(of: (Int, URL?).self) { group in
            for (idx, player) in basePlayers.enumerated() {
                group.addTask { (idx, await oracleElixir.fetchPlayerImageURL(summonerName: player.summonerName)) }
            }
            var results: [Int: URL] = [:]
            for await (idx, url) in group where url != nil {
                results[idx] = url
            }
            return results
        }

        players = basePlayers.enumerated().map { idx, player in
            Player(id: player.id, summonerName: player.summonerName, firstName: player.firstName,
                   lastName: player.lastName, role: player.role,
                   imageURL: imageURLs[idx]?.absoluteString, teamId: player.teamId, teamCode: player.teamCode)
        }.sorted { Self.roleOrder($0.role) < Self.roleOrder($1.role) }
    }
}
