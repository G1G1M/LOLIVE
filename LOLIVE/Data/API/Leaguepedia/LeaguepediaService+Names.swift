//
//  LeaguepediaService+Names.swift
//  LOLIVE
//
//  리그·시즌에 등록된 선수 이름 집합. TournamentPlayers 테이블을 먼저 보고,
//  비어 있으면 ScoreboardPlayers(실제 출전 기록)로 폴백한다.
//

import Foundation

extension LeaguepediaService {
    // MARK: - 선수 이름 목록

    /// 해당 리그·시즌에 등록된 선수 이름 집합 반환.
    /// OnboardingView에서 현재 선수인지 판별할 때 사용한다.
    func playerNames(league: League) async -> Set<String>? {
        guard let leagueName = leaguepediaName(for: league) else { return nil }
        if let cached = await LeaguepediaCache.shared.playerNames(for: leagueName) { return cached }
        guard let overviewPage = await currentOverviewPage(leagueName: leagueName) else { return nil }
        // TournamentPlayers 테이블 우선, 없으면 ScoreboardPlayers fallback
        let primary = await names(overviewPage: overviewPage)
        let result: Set<String>? = (primary?.isEmpty == false)
            ? primary
            : await namesFromScoreboard(overviewPage: overviewPage)
        if let result { await LeaguepediaCache.shared.setPlayerNames(result, for: leagueName) }
        return result
    }

    // MARK: - 선수 이름 수집 (내부)

    /// TournamentPlayers 테이블에서 선수명 집합 반환.
    private func names(overviewPage: String) async -> Set<String>? {
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action", value: "cargoquery"),
            .init(name: "tables", value: "TournamentPlayers"),
            .init(name: "fields", value: "Player,SummonerName"),
            .init(name: "where",  value: "OverviewPage='\(escapeSql(overviewPage))'"),
            .init(name: "limit",  value: "500"),
            .init(name: "format", value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return nil }
        var result = Set<String>()
        for row in resp.cargoquery {
            if let p = row.title["Player"],       !p.isEmpty { result.insert(p.lowercased()) }
            if let s = row.title["SummonerName"], !s.isEmpty { result.insert(s.lowercased()) }
        }
        return result.isEmpty ? nil : result
    }

    /// TournamentPlayers 실패 시 ScoreboardPlayers에서 Link 수집 (fallback).
    private func namesFromScoreboard(overviewPage: String) async -> Set<String>? {
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action", value: "cargoquery"),
            .init(name: "tables", value: "ScoreboardPlayers"),
            .init(name: "fields", value: "Link"),
            .init(name: "where",  value: "OverviewPage='\(escapeSql(overviewPage))'"),
            .init(name: "limit",  value: "500"),
            .init(name: "format", value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return nil }
        var result = Set<String>()
        for row in resp.cargoquery {
            if let l = row.title["Link"], !l.isEmpty { result.insert(l.lowercased()) }
        }
        return result.isEmpty ? nil : result
    }
}
