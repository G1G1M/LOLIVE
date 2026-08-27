//
//  LeaguepediaService+Bans.swift
//  LOLIVE
//
//  Riot API가 밴 데이터를 안 주는 경기의 최종 폴백.
//  Oracle's Elixir 드래프트 조회가 먼저 시도되고, 그것도 실패했을 때만 여기로 온다.
//

import Foundation

extension LeaguepediaService {
    // MARK: - 밴 데이터

    /// Leaguepedia ScoreboardGames에서 게임 밴 목록 반환.
    /// Riot API가 밴 데이터를 제공하지 않는 경기에 대한 보완 데이터.
    /// - Parameter riotGameId: Riot API의 gameId (LOLESPRT_ 접두사 제외)
    func fetchBans(riotGameId: String) async -> (team1Bans: [String], team2Bans: [String])? {
        let cacheKey = CacheKey.leaguepediaBans(riotGameId: riotGameId)
        if let cached: BansCacheEntry = AppDiskCache.get(cacheKey) {
            return (team1Bans: cached.team1Bans, team2Bans: cached.team2Bans)
        }
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action", value: "cargoquery"),
            .init(name: "tables", value: "ScoreboardGames"),
            .init(name: "fields", value: "Team1Bans,Team2Bans"),
            // Leaguepedia는 Riot gameId 앞에 LOLESPRT_ 접두사를 붙여 저장
            .init(name: "where",  value: "GameId='LOLESPRT_\(riotGameId)'"),
            .init(name: "limit",  value: "1"),
            .init(name: "format", value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data),
              let row = resp.cargoquery.first?.title else { return nil }
        let t1 = parseBans(row["Team1Bans"] ?? "")
        let t2 = parseBans(row["Team2Bans"] ?? "")
        guard !t1.isEmpty || !t2.isEmpty else { return nil }
        AppDiskCache.set(cacheKey, value: BansCacheEntry(team1Bans: t1, team2Bans: t2))
        return (team1Bans: t1, team2Bans: t2)
    }

}
