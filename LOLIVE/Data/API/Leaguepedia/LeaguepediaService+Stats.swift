//
//  LeaguepediaService+Stats.swift
//  LOLIVE
//
//  선수 시즌 스탯 · 챔피언픽 · 밴 · 프로필 이미지를 담당하는 Extension.
//
//  [데이터 흐름]
//  1. preloadLeagueStats() — 앱 시작 시 백그라운드에서 리그 전체 데이터 미리 로드
//  2. playerSeasonStats() / playerChampionPicks() — 선수 상세 화면 진입 시 호출
//     → 배치 캐시 히트 시 즉시 반환 (1단계)
//     → 캐시 미스 시 candidateOverviewPages로 최근 시즌 순서대로 탐색 (2단계)
//

import Foundation

extension LeaguepediaService {

    // MARK: - 리그 전체 선로딩

    /// 앱 시작 후 백그라운드에서 리그 전체 스탯·픽을 미리 로드.
    /// 선수 상세 화면 진입 전에 완료되면 API 호출 없이 즉시 반환 가능.
    func preloadLeagueStats(for league: League) async {
        guard let leagueName = leaguepediaName(for: league),
              let overviewPage = await currentOverviewPage(leagueName: leagueName) else { return }
        _ = await allPlayerStats(overviewPage: overviewPage)
        _ = await allChampionPicks(overviewPage: overviewPage)
    }

    // MARK: - 시즌 스탯 (선수 개별)

    /// 선수의 현 시즌 통합 스탯 반환 (승률, KDA, CS/분 등).
    ///
    /// [조회 순서]
    /// 1. 메모리 캐시
    /// 2. 배치 캐시 (preloadLeagueStats가 완료한 경우)
    /// 3. candidateOverviewPages 순서대로 API 탐색
    func playerSeasonStats(summonerName: String, league: League) async -> PlayerSeasonStats? {
        guard let leagueName = leaguepediaName(for: league) else { return nil }

        let cacheKey = "\(summonerName)|\(leagueName)"
        if let cached = await LeaguepediaCache.shared.cachedSeasonStats(key: cacheKey) {
            return cached
        }

        // 1단계: 이미 캐시된 OverviewPage로 먼저 시도 (API 호출 없음)
        if let cachedPage = await LeaguepediaCache.shared.overviewPage(for: leagueName),
           let allStats = await allPlayerStats(overviewPage: cachedPage) {
            let stats = findStats(in: allStats, summonerName: summonerName)
            if let stats, stats.games > 0 {
                await LeaguepediaCache.shared.setSeasonStats(stats, key: cacheKey)
                return stats
            }
        }

        // 2단계: 캐시 미스 → 최근 시즌 OverviewPage 후보 목록 API 조회 후 순서대로 탐색
        let pages = await candidateOverviewPages(leagueName: leagueName)
        for page in pages {
            guard let allStats = await allPlayerStats(overviewPage: page) else { continue }
            let stats = findStats(in: allStats, summonerName: summonerName)
            if let stats, stats.games > 0 {
                await LeaguepediaCache.shared.setSeasonStats(stats, key: cacheKey)
                return stats
            }
        }

        await LeaguepediaCache.shared.setSeasonStats(nil, key: cacheKey)
        return nil
    }

    // MARK: - 챔피언 픽 (선수 개별)

    /// 선수의 현 시즌 챔피언 픽 목록 반환 (게임별 KDA + 승패).
    ///
    /// 배치 캐시 히트 시 개별 API 호출 없이 즉시 반환.
    func playerChampionPicks(summonerName: String, league: League) async -> [ChampionPickEntry]? {
        guard let leagueName = leaguepediaName(for: league),
              let overviewPage = await currentOverviewPage(leagueName: leagueName)
        else { return nil }

        let cacheKey = "v2_\(overviewPage)__\(summonerName)"
        if let cached = await LeaguepediaCache.shared.cachedChampionPicks(key: cacheKey) {
            return cached.isEmpty ? nil : cached
        }

        // 배치 캐시 우선 확인 (preloadLeagueStats 완료 시 API 호출 불필요)
        if let batch = await LeaguepediaCache.shared.allChampionPicksBatch(for: overviewPage) {
            let picks = findPicks(in: batch, summonerName: summonerName)
            await LeaguepediaCache.shared.setChampionPicks(picks, key: cacheKey)
            return picks.isEmpty ? nil : picks
        }

        // 배치 미완료 시 선수 개별 쿼리
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action",  value: "cargoquery"),
            .init(name: "tables",  value: "ScoreboardPlayers,ScoreboardGames"),
            .init(name: "join_on", value: "ScoreboardGames.GameId=ScoreboardPlayers.GameId"),
            .init(name: "fields",  value: "ScoreboardPlayers.Champion=Champion,ScoreboardPlayers.Kills=K,ScoreboardPlayers.Deaths=D,ScoreboardPlayers.Assists=A,ScoreboardGames.Winner=W,ScoreboardGames.Team1=T1,ScoreboardGames.Team2=T2,ScoreboardPlayers.Team=MyTeam,ScoreboardGames.DateTime_UTC=DT"),
            .init(name: "where",   value: "ScoreboardPlayers.OverviewPage='\(escapeSql(overviewPage))' AND ScoreboardPlayers.Link='\(escapeSql(summonerName))'"),
            .init(name: "limit",   value: "500"),
            .init(name: "format",  value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data)
        else { return nil }

        let picks: [ChampionPickEntry] = resp.cargoquery.compactMap { row in
            guard let champion = row.title["Champion"], !champion.isEmpty else { return nil }
            let k = Int(row.title["K"] ?? "0") ?? 0
            let d = Int(row.title["D"] ?? "0") ?? 0
            let a = Int(row.title["A"] ?? "0") ?? 0
            let winner = row.title["W"] ?? ""
            let t1     = row.title["T1"] ?? ""
            let t2     = row.title["T2"] ?? ""
            let myTeam = row.title["MyTeam"] ?? ""
            let won = (winner == "1" && myTeam == t1) || (winner == "2" && myTeam == t2)
            let date = Self.utcDateFmt.date(from: row.title["DT"] ?? "")
            return ChampionPickEntry(champion: champion, kills: k, deaths: d, assists: a,
                                     won: won, date: date)
        }

        await LeaguepediaCache.shared.setChampionPicks(picks, key: cacheKey)
        return picks.isEmpty ? nil : picks
    }

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

    // MARK: - 밴 데이터

    /// Leaguepedia ScoreboardGames에서 게임 밴 목록 반환.
    /// Riot API가 밴 데이터를 제공하지 않는 경기에 대한 보완 데이터.
    /// - Parameter riotGameId: Riot API의 gameId (LOLESPRT_ 접두사 제외)
    func fetchBans(riotGameId: String) async -> (team1Bans: [String], team2Bans: [String])? {
        let cacheKey = "lp_bans_\(riotGameId)"
        // 완료 경기 밴 데이터는 변하지 않으므로 30일 캐싱
        if let cached: BansCacheEntry = AppDiskCache.get(key: cacheKey, maxAge: 30 * 24 * 3600) {
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
        AppDiskCache.set(key: cacheKey, value: BansCacheEntry(team1Bans: t1, team2Bans: t2))
        return (team1Bans: t1, team2Bans: t2)
    }

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

    // MARK: - 스탯 계산 (내부)

    /// 선수의 게임 행(rows)에서 평균 스탯을 계산해 PlayerSeasonStats로 반환.
    func computeStats(from rows: [[String: String]]) -> PlayerSeasonStats {
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
            // GL(게임 길이, 분 단위)이 0이면 CS/분 계산 불가 → 제외
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
            // 데스가 0이면 퍼펙트 KDA → kills+assists 그대로 사용
            kdaRatio:    avgD > 0 ? (avgK + avgA) / avgD : avgK + avgA,
            avgCSPerMin: cspmCount > 0 ? totalCSpm / Double(cspmCount) : 0
        )
    }

    // MARK: - 이름 매칭 헬퍼 (내부)

    /// summonerName으로 스탯 딕셔너리에서 선수를 찾는다.
    ///
    /// Riot API의 summonerName(예: "HADES1")과 Leaguepedia의 Link(예: "Hades1")는
    /// 대소문자가 다를 수 있으므로 아래 순서로 폴백한다:
    /// 1. 정확 일치
    /// 2. "이름 (팀명)" 패턴 (같은 이름 선수 구분용 Leaguepedia 규칙)
    /// 3. 대소문자 무시 일치
    /// 4. 대소문자 무시 + "(팀명)" 패턴
    func findStats(in dict: [String: PlayerSeasonStats],
                   summonerName: String) -> PlayerSeasonStats? {
        let prefix = "\(summonerName) ("
        let lower  = summonerName.lowercased()
        return dict[summonerName]
            ?? dict.first(where: { $0.key.hasPrefix(prefix) })?.value
            ?? dict.first(where: { $0.key.lowercased() == lower })?.value
            ?? dict.first(where: { $0.key.lowercased().hasPrefix("\(lower) (") })?.value
    }

    /// summonerName으로 챔피언픽 딕셔너리에서 선수를 찾는다. findStats와 동일한 폴백 순서.
    func findPicks(in dict: [String: [ChampionPickEntry]],
                   summonerName: String) -> [ChampionPickEntry] {
        let prefix = "\(summonerName) ("
        let lower  = summonerName.lowercased()
        return dict[summonerName]
            ?? dict.first(where: { $0.key.hasPrefix(prefix) })?.value
            ?? dict.first(where: { $0.key.lowercased() == lower })?.value
            ?? dict.first(where: { $0.key.lowercased().hasPrefix("\(lower) (") })?.value
            ?? []
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
