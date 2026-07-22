//
//  LeaguepediaService+History.swift
//  LOLIVE
//
//  Worlds / MSI 등 과거 대회 및 리그 히스토리 경기 데이터를 담당하는 Extension.
//
//  [설계 원칙]
//  - Riot API는 ~1년 이내 경기만 제공 → 그 이전 데이터는 Leaguepedia MatchSchedule 테이블 사용
//  - 완료된 경기 데이터는 변경 가능성이 낮으므로 30일 TTL 캐싱 (시즌 스탯의 24시간보다 길게)
//  - 연도 탭은 1회 API 호출로 전체 목록을 가져오고, 경기 데이터는 탭 선택 시 on-demand 로드
//
//  [호출 흐름]
//  HistoricalMatchesViewModel.load()
//    → historicalYears()        ← 연도 탭 즉시 표시
//    → fetchMatchesFromCacheOnly()  ← 캐시 히트 시 즉시 표시
//    → fetchMatches()           ← 탭 선택 시 API 호출
//

import Foundation

extension LeaguepediaService {

    // MARK: - 연도 목록

    /// 해당 리그의 경기가 있는 연도 목록을 내림차순으로 반환.
    /// Leaguepedia에 해당 리그 Tournaments 테이블을 1회 조회하고 캐싱한다.
    func historicalYears(for league: League) async -> [Int] {
        guard let leagueName = leaguepediaName(for: league) else { return [] }
        let pages = await cachedOrFetchPages(leagueName: leagueName)
        return Array(Set(pages.map { $0.year })).sorted(by: >)
    }

    // MARK: - 캐시 전용 조회 (빠른 첫 화면용)

    /// 디스크 캐시에 있는 연도 경기만 반환 (API 호출 없음).
    /// HistoricalMatchesViewModel 초기 진입 시 이미 캐시된 경기를 즉시 표시하는 데 사용.
    func fetchMatchesFromCacheOnly(for league: League, year: Int) async -> [Match] {
        guard let leagueName = leaguepediaName(for: league) else { return [] }
        let allPages = await cachedOrFetchPages(leagueName: leagueName)
        let yearPages = allPages.filter { $0.year == year }
        var all: [Match] = []
        for entry in yearPages {
            let cacheKey = histCacheKey(leagueName: leagueName, page: entry.page)
            if let cached = await LeaguepediaCache.shared.cachedHistoricalMatches(key: cacheKey) {
                all.append(contentsOf: cached)
            }
        }
        return deduplicated(all)
    }

    // MARK: - 연도별 경기 로드

    /// 특정 연도의 모든 경기를 반환 (캐시 미스 시 API 호출).
    /// 같은 연도에 여러 OverviewPage(예: 플레이오프 + 정규 시즌)가 있으면 전부 합쳐서 반환.
    func fetchMatches(for league: League, year: Int) async -> [Match] {
        guard let leagueName = leaguepediaName(for: league) else { return [] }
        let allPages = await cachedOrFetchPages(leagueName: leagueName)
        let yearPages = allPages.filter { $0.year == year }
        guard !yearPages.isEmpty else { return [] }

        var all: [Match] = []
        for entry in yearPages {
            let cacheKey = histCacheKey(leagueName: leagueName, page: entry.page)
            if let cached = await LeaguepediaCache.shared.cachedHistoricalMatches(key: cacheKey) {
                all.append(contentsOf: cached)
            } else {
                let matches = await matchesForOverviewPage(entry.page, league: league)
                await LeaguepediaCache.shared.setHistoricalMatches(matches, key: cacheKey)
                all.append(contentsOf: matches)
            }
        }
        return deduplicated(all)
    }

    // MARK: - 전체 과거 경기 로드

    /// 모든 연도의 경기를 한꺼번에 로드.
    /// - Parameter excludingYears: 이미 다른 경로에서 로드된 연도를 제외해 중복 요청을 방지.
    func fetchAllHistoricalMatches(for league: League, excludingYears: Set<Int> = []) async -> [Match] {
        guard let leagueName = leaguepediaName(for: league) else { return [] }
        let pages = await cachedOrFetchPages(leagueName: leagueName)

        var all: [Match] = []
        for entry in pages where !excludingYears.contains(entry.year) {
            let cacheKey = histCacheKey(leagueName: leagueName, page: entry.page)
            if let cached = await LeaguepediaCache.shared.cachedHistoricalMatches(key: cacheKey) {
                all.append(contentsOf: cached)
            } else {
                let matches = await matchesForOverviewPage(entry.page, league: league)
                await LeaguepediaCache.shared.setHistoricalMatches(matches, key: cacheKey)
                all.append(contentsOf: matches)
            }
        }
        return all
    }

    // MARK: - 내부 헬퍼

    /// 대회 페이지 목록을 캐시에서 읽거나 API로 가져오는 공통 경로.
    private func cachedOrFetchPages(leagueName: String) async -> [LPTournamentEntry] {
        let pagesKey = "ovpages_\(leagueName)"
        if let cached = await LeaguepediaCache.shared.cachedTournamentPages(key: pagesKey) {
            return cached
        }
        let pages = await allOverviewPagesForLeague(leagueName: leagueName)
        if !pages.isEmpty {
            await LeaguepediaCache.shared.setTournamentPages(pages, key: pagesKey)
        }
        return pages
    }

    /// Leaguepedia Tournaments 테이블에서 해당 리그의 모든 OverviewPage와 연도를 가져옴.
    ///
    /// Worlds / MSI는 Leagues 조인 없이 OverviewPage 이름 패턴으로 직접 조회.
    /// 일반 리그는 League_Short 컬럼으로 조인해 필터링.
    private func allOverviewPagesForLeague(leagueName: String) async -> [LPTournamentEntry] {
        var c = URLComponents(string: baseURL)!

        if leagueName == "Worlds" || leagueName == "MSI" {
            // 국제 대회: OverviewPage 이름 패턴 매칭이 Leagues 조인보다 안정적
            let pattern = leagueName == "Worlds"
                ? "%Season World Championship%"
                : "%Mid-Season Invitational%"
            c.queryItems = [
                .init(name: "action",   value: "cargoquery"),
                .init(name: "tables",   value: "Tournaments"),
                .init(name: "fields",   value: "Tournaments.OverviewPage,Tournaments.DateStart"),
                .init(name: "where",    value: "Tournaments.OverviewPage LIKE '\(pattern)'"),
                .init(name: "order_by", value: "Tournaments.DateStart DESC"),
                .init(name: "limit",    value: "20"),
                .init(name: "format",   value: "json"),
            ]
        } else {
            c.queryItems = [
                .init(name: "action",   value: "cargoquery"),
                .init(name: "tables",   value: "Tournaments,Leagues"),
                .init(name: "join_on",  value: "Tournaments.League=Leagues.League"),
                .init(name: "fields",   value: "Tournaments.OverviewPage,Tournaments.DateStart"),
                .init(name: "where",    value: "Leagues.League_Short='\(escapeSql(leagueName))'"),
                .init(name: "order_by", value: "Tournaments.DateStart DESC"),
                .init(name: "limit",    value: "50"),
                .init(name: "format",   value: "json"),
            ]
        }

        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return [] }

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return resp.cargoquery.compactMap { row -> LPTournamentEntry? in
            guard let page = row.title["OverviewPage"], !page.isEmpty,
                  let dateStr = row.title["DateStart"],
                  let date = fmt.date(from: dateStr) else { return nil }
            let year = Calendar.current.component(.year, from: date)
            return LPTournamentEntry(page: page, year: year)
        }
    }

    /// 단일 OverviewPage에 대한 MatchSchedule 테이블 조회 → [Match] 변환.
    ///
    /// 500행씩 페이지네이션하고, 팀 이미지는 Teams 테이블 배치 조회 후
    /// 없으면 URL 패턴 폴백 (`lpTeamLogoURL`)을 사용한다.
    private func matchesForOverviewPage(_ overviewPage: String, league: League) async -> [Match] {
        var allRows: [[String: String]] = []
        var offset = 0
        let batchSize = 500

        while !Task.isCancelled {
            var c = URLComponents(string: baseURL)!
            c.queryItems = [
                .init(name: "action",   value: "cargoquery"),
                .init(name: "tables",   value: "MatchSchedule"),
                .init(name: "fields",   value: "MatchId,DateTime_UTC,Team1,Team2,Team1Score,Team2Score,Winner,Tab"),
                .init(name: "where",    value: "OverviewPage='\(escapeSql(overviewPage))' AND Team1 IS NOT NULL AND Team2 IS NOT NULL AND DateTime_UTC IS NOT NULL"),
                .init(name: "order_by", value: "DateTime_UTC ASC"),
                .init(name: "offset",   value: "\(offset)"),
                .init(name: "limit",    value: "\(batchSize)"),
                .init(name: "format",   value: "json"),
            ]
            guard let url = c.url,
                  let data = await cargoData(url: url),
                  let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { break }
            let batch = resp.cargoquery.map { $0.title }
            allRows.append(contentsOf: batch)
            if batch.count < batchSize { break }
            offset += batchSize
        }

        // 고유 팀명 추출 → 이미지 배치 조회 (Teams 테이블 1회)
        let uniqueTeamNames = Set(allRows.flatMap {
            [$0["Team1"], $0["Team2"]].compactMap { $0 }.filter { !$0.isEmpty }
        })
        let teamImages = await fetchTeamImageURLs(uniqueTeamNames)

        // Leaguepedia DateTime_UTC는 "yyyy-MM-dd HH:mm:ss" 또는 ISO8601 형식
        let fmt1 = DateFormatter()
        fmt1.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt1.timeZone = TimeZone(identifier: "UTC")
        let fmt2 = ISO8601DateFormatter()

        return allRows.compactMap { row -> Match? in
            guard let dateStr = row["DateTime UTC"], !dateStr.isEmpty,
                  let startTime = fmt1.date(from: dateStr) ?? fmt2.date(from: dateStr),
                  let team1 = row["Team1"], !team1.isEmpty,
                  let team2 = row["Team2"], !team2.isEmpty
            else { return nil }

            let rawId = row["MatchId"]?.trimmingCharacters(in: .whitespaces) ?? ""
            // MatchId가 없는 오래된 경기는 팀+날짜 조합으로 고유 ID 생성
            let matchId = rawId.isEmpty
                ? "lp_\(overviewPage)_\(team1)_\(team2)_\(dateStr)"
                : "lp_\(rawId)"

            let scoreA = Int(row["Team1Score"] ?? "") ?? 0
            let scoreB = Int(row["Team2Score"] ?? "") ?? 0
            let winner = row["Winner"] ?? ""
            let state: MatchState = winner.isEmpty ? .unstarted : .completed

            let blockNameRaw = row["Tab"]?.trimmingCharacters(in: .whitespaces) ?? ""
            let blockName: String? = blockNameRaw.isEmpty ? nil : blockNameRaw

            // Teams 테이블에 없으면 파일명 패턴으로 폴백
            let imageA = teamImages[team1] ?? lpTeamLogoURL(team1)
            let imageB = teamImages[team2] ?? lpTeamLogoURL(team2)
            let teamA = Team(id: "lp_\(team1)", name: team1, code: team1, imageURL: imageA)
            let teamB = Team(id: "lp_\(team2)", name: team2, code: team2, imageURL: imageB)

            return Match(id: matchId, league: league,
                         teamA: teamA, teamB: teamB,
                         scoreA: scoreA, scoreB: scoreB,
                         startTime: startTime, state: state,
                         blockName: blockName)
        }
    }

    /// Leaguepedia Teams 테이블에서 팀 로고 URL을 배치 조회.
    /// 조회 결과: [팀코드(Short): FilePath URL]
    private func fetchTeamImageURLs(_ names: Set<String>) async -> [String: String] {
        guard !names.isEmpty else { return [:] }
        let inClause = names.map { "'\(escapeSql($0))'" }.joined(separator: ",")
        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action", value: "cargoquery"),
            .init(name: "tables", value: "Teams"),
            .init(name: "fields", value: "Teams.Short=Short,Teams.Image=Image"),
            .init(name: "where",  value: "Teams.Short IN (\(inClause))"),
            .init(name: "limit",  value: "50"),
            .init(name: "format", value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return [:] }

        var result: [String: String] = [:]
        for row in resp.cargoquery {
            guard let short = row.title["Short"], !short.isEmpty,
                  let image = row.title["Image"], !image.isEmpty else { continue }
            let encoded = image.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? image
            result[short] = "https://lol.fandom.com/wiki/Special:FilePath/\(encoded)"
        }
        return result
    }

    /// Teams 테이블에 이미지가 없을 때 사용하는 파일명 패턴 폴백.
    /// "T1logo std.png" 같은 형식으로 Leaguepedia에 저장된 파일에 직접 접근.
    private func lpTeamLogoURL(_ name: String) -> String? {
        let fileName = "\(name)logo std.png"
        guard let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return "https://lol.fandom.com/wiki/Special:FilePath/\(encoded)"
    }

    // MARK: - 유틸리티

    /// histCacheKey: 리그명 + OverviewPage를 조합해 디스크 캐시 키 생성.
    /// 경로 구분자(/,  )를 _로 치환해 파일명에 사용 가능한 형태로 만든다.
    private func histCacheKey(leagueName: String, page: String) -> String {
        let safePage = page
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "histv2_\(leagueName)_\(safePage)"
    }

    /// 중복 Match 제거 (동일 id 유지, 첫 번째 등장 우선).
    func deduplicated(_ matches: [Match]) -> [Match] {
        var seen = Set<String>()
        return matches.filter { seen.insert($0.id).inserted }
    }
}
