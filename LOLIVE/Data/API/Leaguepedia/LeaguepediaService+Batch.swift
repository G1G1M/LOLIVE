//
//  LeaguepediaService+Batch.swift
//  LOLIVE
//
//  리그 단위 배치 로드. Leaguepedia는 레이트리밋이 잦아서(공식 문서 없음, 실측으로 확인)
//  선수마다 개별 호출하는 대신 리그 전체를 500행씩 페이지네이션해 한 번에 받아 캐싱한다.
//

import Foundation

extension LeaguepediaService {
    // MARK: - 배치 로드 (내부)

    /// 리그 전체 선수의 챔피언 픽을 한 번에 로드.
    /// 500행씩 페이지네이션 → [Link: [ChampionPickEntry]] 형태로 캐싱.
    func allChampionPicks(overviewPage: String) async -> [String: [ChampionPickEntry]]? {
        if let cached = await LeaguepediaCache.shared.allChampionPicksBatch(for: overviewPage) {
            return cached
        }
        var allRows: [[String: String]] = []
        var offset = 0
        let batchSize = 500

        while !Task.isCancelled {
            var c = URLComponents(string: baseURL)!
            c.queryItems = [
                .init(name: "action",  value: "cargoquery"),
                .init(name: "tables",  value: "ScoreboardPlayers,ScoreboardGames"),
                .init(name: "join_on", value: "ScoreboardGames.GameId=ScoreboardPlayers.GameId"),
                .init(name: "fields",  value: "ScoreboardPlayers.Link=L,ScoreboardPlayers.Champion=Champion,ScoreboardPlayers.Kills=K,ScoreboardPlayers.Deaths=D,ScoreboardPlayers.Assists=A,ScoreboardGames.Winner=W,ScoreboardGames.Team1=T1,ScoreboardGames.Team2=T2,ScoreboardPlayers.Team=MyTeam,ScoreboardGames.DateTime_UTC=DT"),
                .init(name: "where",   value: "ScoreboardPlayers.OverviewPage='\(escapeSql(overviewPage))'"),
                .init(name: "offset",  value: "\(offset)"),
                .init(name: "limit",   value: "\(batchSize)"),
                .init(name: "format",  value: "json"),
            ]
            guard let url = c.url,
                  let data = await cargoData(url: url),
                  let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { break }
            let batch = resp.cargoquery.map { $0.title }
            allRows.append(contentsOf: batch)
            if batch.count < batchSize { break }
            offset += batchSize
        }

        guard !allRows.isEmpty else { return nil }

        var result: [String: [ChampionPickEntry]] = [:]
        for row in allRows {
            let link = row["L"] ?? ""
            guard !link.isEmpty, let champion = row["Champion"], !champion.isEmpty else { continue }
            let k = Int(row["K"] ?? "0") ?? 0
            let d = Int(row["D"] ?? "0") ?? 0
            let a = Int(row["A"] ?? "0") ?? 0
            let myTeam = row["MyTeam"] ?? ""
            let winner = row["W"] ?? ""
            let t1     = row["T1"] ?? ""
            let t2     = row["T2"] ?? ""
            let won = (winner == "1" && myTeam == t1) || (winner == "2" && myTeam == t2)
            let date = Self.utcDateFmt.date(from: row["DT"] ?? "")
            result[link, default: []].append(
                ChampionPickEntry(champion: champion, kills: k, deaths: d,
                                  assists: a, won: won, date: date)
            )
        }
        await LeaguepediaCache.shared.setAllChampionPicksBatch(result, for: overviewPage)
        return result.isEmpty ? nil : result
    }

    /// 리그 전체 선수의 시즌 스탯을 한 번에 로드.
    /// 500행씩 페이지네이션 → Link 기준 그룹화 → [Link: PlayerSeasonStats] 캐싱.
    func allPlayerStats(overviewPage: String) async -> [String: PlayerSeasonStats]? {
        if let cached = await LeaguepediaCache.shared.allPlayerStats(for: overviewPage) {
            return cached
        }
        var allRows: [[String: String]] = []
        var offset = 0
        let batchSize = 500

        while !Task.isCancelled {
            var c = URLComponents(string: baseURL)!
            c.queryItems = [
                .init(name: "action",  value: "cargoquery"),
                .init(name: "tables",  value: "ScoreboardGames,ScoreboardPlayers"),
                .init(name: "join_on", value: "ScoreboardGames.GameId=ScoreboardPlayers.GameId"),
                .init(name: "fields",  value: "ScoreboardPlayers.Link=L,ScoreboardPlayers.Kills=K,ScoreboardPlayers.Deaths=D,ScoreboardPlayers.Assists=A,ScoreboardPlayers.CS=CS,ScoreboardGames.Gamelength_Number=GL,ScoreboardGames.Winner=W,ScoreboardGames.Team1=T1,ScoreboardGames.Team2=T2,ScoreboardPlayers.Team=MyTeam"),
                .init(name: "where",   value: "ScoreboardPlayers.OverviewPage='\(escapeSql(overviewPage))'"),
                .init(name: "offset",  value: "\(offset)"),
                .init(name: "limit",   value: "\(batchSize)"),
                .init(name: "format",  value: "json"),
            ]
            guard let url = c.url,
                  let data = await cargoData(url: url),
                  let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { break }
            let batch = resp.cargoquery.map { $0.title }
            allRows.append(contentsOf: batch)
            if batch.count < batchSize { break }
            offset += batchSize
        }

        guard !allRows.isEmpty else { return nil }

        // Link(소환사명) 기준으로 행을 그룹화한 뒤 스탯 계산
        var playerRows: [String: [[String: String]]] = [:]
        for row in allRows {
            let link = row["L"] ?? ""; guard !link.isEmpty else { continue }
            playerRows[link, default: []].append(row)
        }
        var result: [String: PlayerSeasonStats] = [:]
        for (link, rows) in playerRows {
            result[link] = computeStats(from: rows)
        }
        await LeaguepediaCache.shared.setAllPlayerStats(result, for: overviewPage)
        return result
    }

}
