//
//  LeaguepediaService.swift
//  LOLIVE
//

import Foundation

struct LeaguepediaService: Sendable {

    static let shared = LeaguepediaService()

    private let baseURL = "https://lol.fandom.com/api.php"

    // MARK: - Public

    /// Riot API League 객체를 받아 해당 리그의 현재 시즌 공식 선수명 집합(소문자)을 반환.
    /// TournamentPlayers → ScoreboardPlayers 순서로 시도. 둘 다 실패 시 nil.
    func playerNames(league: League) async -> Set<String>? {
        guard let leagueName = leaguepediaName(for: league) else { return nil }
        guard let overviewPage = await currentOverviewPage(leagueName: leagueName) else { return nil }
        if let primary = await names(overviewPage: overviewPage), !primary.isEmpty {
            return primary
        }
        return await namesFromScoreboard(overviewPage: overviewPage)
    }

    // MARK: - League name mapping

    private func leaguepediaName(for league: League) -> String? {
        let lower = league.name.lowercased()
        switch true {
        case lower == "lck":                                          return "LCK"
        case lower.contains("챌린저스") && lower.contains("lck"),
             lower.contains("challengers") && lower.contains("lck"),
             lower == "lck cl":                                       return "LCK CL"
        case lower == "lpl":                                          return "LPL"
        case lower.contains("lpl") && (lower.contains("dev") || lower.contains("ldl")):
                                                                      return "LDL"
        case lower == "lec", lower.contains("emea championship"):     return "LEC"
        case lower == "lcs":                                          return "LCS"
        case lower.contains("lcs") && lower.contains("acad"):        return "LCS Academy"
        case lower == "pcs":                                          return "PCS"
        case lower == "vcs":                                          return "VCS"
        case lower == "cblol":                                        return "CBLOL"
        case lower.contains("cblol") && lower.contains("acad"):      return "CBLOL Academy"
        case lower == "ljl":                                          return "LJL"
        case lower == "lco":                                          return "LCO"
        case lower == "lla":                                          return "LLA"
        default:                                                       return nil
        }
    }

    // MARK: - Private queries

    private func currentOverviewPage(leagueName: String) async -> String? {
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action",  value: "cargoquery"),
            .init(name: "tables",  value: "Tournaments"),
            .init(name: "fields",  value: "OverviewPage,DateStart,Date"),
            .init(name: "where",   value: "League='\(escapeSql(leagueName))'"),
            .init(name: "orderby", value: "DateStart DESC"),
            .init(name: "limit",   value: "5"),
            .init(name: "format",  value: "json"),
        ]
        guard let url = c.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return nil }

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        for row in resp.cargoquery {
            guard let page  = row.title["OverviewPage"],
                  let start = row.title["DateStart"].flatMap({ fmt.date(from: $0) }),
                  let end   = row.title["Date"].flatMap({ fmt.date(from: $0) }),
                  now >= start, now <= end else { continue }
            return page
        }
        return resp.cargoquery.first?.title["OverviewPage"]
    }

    /// TournamentPlayers: 등록 로스터 기준 (Player + SummonerName 두 필드 모두 수집)
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
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return nil }

        var result = Set<String>()
        for row in resp.cargoquery {
            if let p = row.title["Player"],       !p.isEmpty { result.insert(p.lowercased()) }
            if let s = row.title["SummonerName"], !s.isEmpty { result.insert(s.lowercased()) }
        }
        return result.isEmpty ? nil : result
    }

    /// ScoreboardPlayers: 실제 경기 출전 데이터 기준 폴백
    private func namesFromScoreboard(overviewPage: String) async -> Set<String>? {
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action", value: "cargoquery"),
            .init(name: "tables", value: "ScoreboardPlayers"),
            .init(name: "fields", value: "PlayerRedirect,Link"),
            .init(name: "where",  value: "OverviewPage='\(escapeSql(overviewPage))'"),
            .init(name: "limit",  value: "500"),
            .init(name: "format", value: "json"),
        ]
        guard let url = c.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return nil }

        var result = Set<String>()
        for row in resp.cargoquery {
            if let p = row.title["PlayerRedirect"], !p.isEmpty { result.insert(p.lowercased()) }
            if let l = row.title["Link"],            !l.isEmpty { result.insert(l.lowercased()) }
        }
        return result.isEmpty ? nil : result
    }

    private func escapeSql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }
}

// MARK: - Cargo API decodable models (file-private)

private struct CargoResp: Decodable {
    let cargoquery: [CargoRow]
}

private struct CargoRow: Decodable {
    let title: [String: String]
}
