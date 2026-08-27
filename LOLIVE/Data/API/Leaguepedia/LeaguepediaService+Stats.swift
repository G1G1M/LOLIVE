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

}
