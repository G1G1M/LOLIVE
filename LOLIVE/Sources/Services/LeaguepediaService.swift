//
//  LeaguepediaService.swift
//  LOLIVE
//

import Foundation

struct LeaguepediaService: Sendable {

    static let shared = LeaguepediaService()

    private let baseURL = "https://lol.fandom.com/api.php"

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 15
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    // MARK: - Public

    /// 선수 시즌 스탯 반환.
    /// 리그 전체 스탯을 백그라운드에서 미리 로드. 이미 캐시된 경우 즉시 반환.
    func preloadLeagueStats(for league: League) async {
        guard let leagueName = leaguepediaName(for: league),
              let overviewPage = await currentOverviewPage(leagueName: leagueName) else { return }
        _ = await allPlayerStats(overviewPage: overviewPage)
    }

    /// 리그 전체를 배치로 한 번에 로드하고 캐싱 — 같은 리그의 두 번째 선수부터는 즉시 반환.
    func playerSeasonStats(summonerName: String, league: League) async -> PlayerSeasonStats? {
        guard let leagueName = leaguepediaName(for: league) else { return nil }

        let cacheKey = "\(summonerName)|\(leagueName)"
        if let cached = await LeaguepediaCache.shared.cachedSeasonStats(key: cacheKey) {
            return cached
        }

        guard let overviewPage = await currentOverviewPage(leagueName: leagueName) else { return nil }
        guard let allStats = await allPlayerStats(overviewPage: overviewPage) else {
            await LeaguepediaCache.shared.setSeasonStats(nil, key: cacheKey)
            return nil
        }

        if let stats = allStats[summonerName], stats.games > 0 {
            await LeaguepediaCache.shared.setSeasonStats(stats, key: cacheKey)
            return stats
        }

        let prefix = "\(summonerName) ("
        if let canonical = allStats.keys.first(where: { $0.hasPrefix(prefix) }),
           let stats = allStats[canonical], stats.games > 0 {
            await LeaguepediaCache.shared.setSeasonStats(stats, key: cacheKey)
            return stats
        }

        await LeaguepediaCache.shared.setSeasonStats(nil, key: cacheKey)
        return nil
    }

    /// 게임 벤 데이터 반환. team1Bans = Team1(첫 번째 팀), team2Bans = Team2(두 번째 팀).
    func fetchBans(riotGameId: String) async -> (team1Bans: [String], team2Bans: [String])? {
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action", value: "cargoquery"),
            .init(name: "tables", value: "ScoreboardGames"),
            .init(name: "fields", value: "Team1Bans,Team2Bans"),
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
        return (team1Bans: t1, team2Bans: t2)
    }

    /// 소환사명으로 Leaguepedia Players 테이블에서 선수 프로필 이미지 URL 반환.
    func fetchPlayerImageURL(summonerName: String) async -> URL? {
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action", value: "cargoquery"),
            .init(name: "tables", value: "Players"),
            .init(name: "fields", value: "Players.Photo"),
            .init(name: "where",  value: "Players.ID='\(escapeSql(summonerName))'"),
            .init(name: "limit",  value: "1"),
            .init(name: "format", value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data),
              let photo = resp.cargoquery.first?.title["Photo"], !photo.isEmpty else { return nil }
        let encoded = photo.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photo
        return URL(string: "https://lol.fandom.com/wiki/Special:FilePath/\(encoded)")
    }

    func playerNames(league: League) async -> Set<String>? {
        guard let leagueName = leaguepediaName(for: league) else { return nil }
        if let cached = await LeaguepediaCache.shared.playerNames(for: leagueName) { return cached }
        guard let overviewPage = await currentOverviewPage(leagueName: leagueName) else { return nil }
        let primary = await names(overviewPage: overviewPage)
        let result: Set<String>? = (primary?.isEmpty == false) ? primary : await namesFromScoreboard(overviewPage: overviewPage)
        if let result { await LeaguepediaCache.shared.setPlayerNames(result, for: leagueName) }
        return result
    }

    // MARK: - League name mapping

    private func leaguepediaName(for league: League) -> String? {
        let lower = league.name.lowercased().trimmingCharacters(in: .whitespaces)
        let slug  = league.slug.lowercased().trimmingCharacters(in: .whitespaces)
        switch true {
        case lower == "lck" || slug == "lck":                         return "LCK"
        case lower.contains("챌린저스") && (lower.contains("lck") || slug.contains("lck")),
             lower.contains("challengers") && (lower.contains("lck") || slug.contains("lck")),
             lower == "lck cl", slug == "lck-cl", slug == "lck_cl",
             slug == "lck_challengers_league":                         return "LCK CL"
        case lower == "lpl" || slug == "lpl":                         return "LPL"
        case (lower.contains("lpl") || slug.contains("lpl")) &&
             (lower.contains("dev") || lower.contains("ldl") ||
              slug.contains("dev") || slug.contains("ldl")):          return "LDL"
        case lower == "lec" || slug == "lec",
             lower.contains("emea championship"):                      return "LEC"
        case lower == "lcs" || slug == "lcs":                         return "LCS"
        case (lower.contains("lcs") || slug.contains("lcs")) &&
             (lower.contains("acad") || slug.contains("acad")):       return "LCS Academy"
        case lower == "pcs" || slug == "pcs":                         return "PCS"
        case lower == "vcs" || slug == "vcs":                         return "VCS"
        case lower == "cblol" || slug == "cblol":                     return "CBLOL"
        case (lower.contains("cblol") || slug.contains("cblol")) &&
             (lower.contains("acad") || slug.contains("acad")):       return "CBLOL Academy"
        case lower == "ljl" || slug == "ljl":                         return "LJL"
        case lower == "lco" || slug == "lco":                         return "LCO"
        case lower == "lla" || slug == "lla":                         return "LLA"
        case lower == "lcp" || slug == "lcp":                         return "LCP"
        default:                                                        return nil
        }
    }

    // MARK: - Batch: 토너먼트 전체 선수 스탯 한 번에 로드

    /// overviewPage 내 모든 선수 스탯을 500행씩 페이지네이션해서 가져온 뒤 캐싱.
    /// 결과: [Link → PlayerSeasonStats] (Link는 Leaguepedia canonical 이름)
    private func allPlayerStats(overviewPage: String) async -> [String: PlayerSeasonStats]? {
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

        // Link 기준으로 그룹화 후 스탯 계산
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

    private func computeStats(from rows: [[String: String]]) -> PlayerSeasonStats {
        var wins = 0
        var totalK = 0.0, totalD = 0.0, totalA = 0.0
        var totalCSpm = 0.0, cspmCount = 0

        for row in rows {
            let winner = row["W"] ?? ""; let t1 = row["T1"] ?? ""
            let t2 = row["T2"] ?? ""; let myTeam = row["MyTeam"] ?? ""
            if (winner == "1" && myTeam == t1) || (winner == "2" && myTeam == t2) { wins += 1 }
            totalK += Double(row["K"] ?? "") ?? 0
            totalD += Double(row["D"] ?? "") ?? 0
            totalA += Double(row["A"] ?? "") ?? 0
            if let gl = Double(row["GL"] ?? ""), gl > 0,
               let cs = Double(row["CS"] ?? ""), cs >= 0 {
                totalCSpm += cs / gl; cspmCount += 1
            }
        }
        let n = Double(rows.count)
        let avgK = totalK / n, avgD = totalD / n, avgA = totalA / n
        return PlayerSeasonStats(
            games:       rows.count,
            winRate:     Double(wins) / n,
            avgKills:    avgK,
            avgDeaths:   avgD,
            avgAssists:  avgA,
            kdaRatio:    avgD > 0 ? (avgK + avgA) / avgD : avgK + avgA,
            avgCSPerMin: cspmCount > 0 ? totalCSpm / Double(cspmCount) : 0
        )
    }

    // MARK: - Overview Page

    private func currentOverviewPage(leagueName: String) async -> String? {
        if let cached = await LeaguepediaCache.shared.overviewPage(for: leagueName) { return cached }

        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action",   value: "cargoquery"),
            .init(name: "tables",   value: "Tournaments,Leagues"),
            .init(name: "join_on",  value: "Tournaments.League=Leagues.League"),
            .init(name: "fields",   value: "Tournaments.OverviewPage,Tournaments.DateStart,Tournaments.Date"),
            .init(name: "where",    value: "Leagues.League_Short='\(escapeSql(leagueName))'"),
            .init(name: "order_by", value: "Tournaments.DateStart DESC"),
            .init(name: "limit",    value: "10"),
            .init(name: "format",   value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return nil }

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()

        var result: String?
        for row in resp.cargoquery {
            guard let page  = row.title["OverviewPage"],
                  let start = row.title["DateStart"].flatMap({ fmt.date(from: $0) }),
                  let end   = row.title["Date"].flatMap({ fmt.date(from: $0) }),
                  now >= start, now <= end else { continue }
            result = page; break
        }
        if result == nil {
            result = resp.cargoquery.first(where: {
                guard let s = fmt.date(from: $0.title["DateStart"] ?? "") else { return false }
                return s <= now
            })?.title["OverviewPage"]
        }
        result = result ?? resp.cargoquery.last?.title["OverviewPage"]

        if let result { await LeaguepediaCache.shared.setOverviewPage(result, for: leagueName) }
        return result
    }

    // MARK: - playerNames helpers

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

    // MARK: - Network

    private func cargoData(url: URL) async -> Data? {
        await LeaguepediaRateLimiter.shared.claimSlot()
        guard !Task.isCancelled else { return nil }

        var request = URLRequest(url: url)
        request.setValue("LOLIVE/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await Self.session.data(for: request)
            let http = response as? HTTPURLResponse
            guard isRateLimited(data) else { return data }

            let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 10.0
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return nil }

            await LeaguepediaRateLimiter.shared.claimSlot()
            guard !Task.isCancelled else { return nil }
            let (data2, _) = try await Self.session.data(for: request)
            return isRateLimited(data2) ? nil : data2
        } catch {
            return nil
        }
    }

    private func isRateLimited(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err  = json["error"] as? [String: Any],
              let code = err["code"] as? String
        else { return false }
        return code == "ratelimited"
    }

    private func escapeSql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }

    private func parseBans(_ str: String) -> [String] {
        str.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Rate Limiter (1.5초 간격)

private actor LeaguepediaRateLimiter {
    static let shared = LeaguepediaRateLimiter()
    private var nextSlotTime = Date.distantPast
    private let slotInterval: TimeInterval = 1.5

    func claimSlot() async {
        guard !Task.isCancelled else { return }
        let now = Date()
        let mySlot = max(now, nextSlotTime)
        nextSlotTime = mySlot.addingTimeInterval(slotInterval)
        let wait = mySlot.timeIntervalSince(now)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }
}

// MARK: - Cache (메모리 + 디스크)

private actor LeaguepediaCache {
    static let shared = LeaguepediaCache()

    private var overviewPages:     [String: String]                      = [:]
    private var playerNameSets:    [String: Set<String>]                 = [:]
    private var seasonStats:       [String: PlayerSeasonStats?]          = [:]
    private var allPlayerStatsDic: [String: [String: PlayerSeasonStats]] = [:]

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeaguepediaStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let maxAge: TimeInterval = 24 * 3600  // 24시간

    func overviewPage(for leagueName: String) -> String? { overviewPages[leagueName] }
    func setOverviewPage(_ page: String, for leagueName: String) { overviewPages[leagueName] = page }

    func playerNames(for leagueName: String) -> Set<String>? { playerNameSets[leagueName] }
    func setPlayerNames(_ names: Set<String>, for leagueName: String) { playerNameSets[leagueName] = names }

    func cachedSeasonStats(key: String) -> PlayerSeasonStats?? { seasonStats[key] }
    func setSeasonStats(_ stats: PlayerSeasonStats?, key: String) { seasonStats[key] = .some(stats) }

    /// 메모리 → 디스크 순으로 탐색. 디스크 항목이 24시간 초과면 무효.
    func allPlayerStats(for page: String) -> [String: PlayerSeasonStats]? {
        if let mem = allPlayerStatsDic[page] { return mem }
        let file = Self.cacheFile(for: page)
        guard let data = try? Data(contentsOf: file),
              let wrapper = try? JSONDecoder().decode(DiskWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < Self.maxAge
        else { return nil }
        allPlayerStatsDic[page] = wrapper.stats
        return wrapper.stats
    }

    func setAllPlayerStats(_ stats: [String: PlayerSeasonStats], for page: String) {
        allPlayerStatsDic[page] = stats
        let wrapper = DiskWrapper(savedAt: Date(), stats: stats)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.cacheFile(for: page), options: .atomic)
        }
    }

    private static func cacheFile(for page: String) -> URL {
        let safe = page.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }

    private struct DiskWrapper: Codable {
        let savedAt: Date
        let stats: [String: PlayerSeasonStats]
    }
}

// MARK: - Cargo models

private struct CargoResp: Decodable {
    let cargoquery: [CargoRow]
}

private struct CargoRow: Decodable {
    let title: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: FlexValue].self, forKey: .title)
        title = raw.mapValues { $0.stringValue }
    }

    enum CodingKeys: String, CodingKey { case title }

    private struct FlexValue: Decodable {
        let stringValue: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { stringValue = s; return }
            if let n = try? c.decode(Double.self) {
                stringValue = n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
                return
            }
            if let b = try? c.decode(Bool.self) { stringValue = b ? "1" : "0"; return }
            stringValue = ""
        }
    }
}
