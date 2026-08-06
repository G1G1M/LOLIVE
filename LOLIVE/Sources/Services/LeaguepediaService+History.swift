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
import os

private let reconcileLPLogger = Logger(subsystem: "com.lolive", category: "Reconcile")

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

    // MARK: - Riot 미보고 결과 보완 (케스파컵 등)

    /// 케스파컵처럼 Riot Esports API가 경기 상태/스코어를 갱신해주지 않는 대회를 위해,
    /// 현재 진행 중인 대회의 Leaguepedia 실제 결과를 가져온다.
    /// Worlds/MSI 과거 기록용 30일 캐시와 달리, 진행 중 대회라 15분 TTL로 짧게 캐싱한다.
    func fetchLiveTournamentResults(for league: League) async -> [Match] {
        guard let leagueName = leaguepediaName(for: league) else {
            #if DEBUG
            reconcileLPLogger.debug("🔎 [Reconcile] leaguepediaName(for: \(league.name)) = nil — 리그명 매핑 실패")
            #endif
            return []
        }
        let pages = await cachedOrFetchPages(leagueName: leagueName)
        guard let currentPage = currentTournamentPage(from: pages) else {
            #if DEBUG
            reconcileLPLogger.debug("🔎 [Reconcile] \(leagueName) 대회 페이지 목록이 비어있음 (pages.count=\(pages.count))")
            #endif
            return []
        }
        #if DEBUG
        reconcileLPLogger.debug("🔎 [Reconcile] \(leagueName) 현재 페이지: \(currentPage.page)")
        #endif

        let cacheKey = "lpresults_\(leagueName)_\(currentPage.page)"
        if let cached: [Match] = AppDiskCache.get(key: cacheKey, maxAge: 15 * 60) {
            #if DEBUG
            reconcileLPLogger.debug("🔎 [Reconcile] \(currentPage.page) 캐시 히트 \(cached.count)건 (15분 이내)")
            #endif
            return cached
        }

        let matches = await matchesForOverviewPage(currentPage.page, league: league)
        #if DEBUG
        reconcileLPLogger.debug("🔎 [Reconcile] \(currentPage.page) API 조회 \(matches.count)건")
        #endif
        if !matches.isEmpty { AppDiskCache.set(key: cacheKey, value: matches) }
        return matches
    }

    /// pages는 DateStart 내림차순 정렬돼 있음 — 그중 "이미 시작한" 대회 중 가장 최근 것을 고른다.
    /// 정규시즌 도중에도 플레이오프 페이지가 미래 DateStart로 이미 등록돼 있는 경우가 있어서,
    /// 그냥 pages.first(가장 최근 DateStart)를 쓰면 아직 시작도 안 한 플레이오프를 "현재 대회"로
    /// 잘못 고르게 된다 (실제로 겪은 버그 — 그 페이지엔 당연히 경기가 없어서 보정이 항상 실패했음).
    /// 아직 아무 대회도 시작 안 했으면(프리시즌 등) 첫 번째로 폴백한다.
    private func currentTournamentPage(from pages: [LPTournamentEntry]) -> LPTournamentEntry? {
        pages.first(where: { $0.dateStart <= Date() }) ?? pages.first
    }

    /// Riot 경기 목록 중 (1) 시작 시각이 한참 지났는데도 `unstarted`로 멈춰있거나
    /// (2) `completed`인데 스코어가 0:0으로 비어 있는(=Riot이 결과를 안 준) 항목,
    /// (3) `inProgress`인데 90분 넘게 스코어 변화가 없는(=실제론 끝났는데 Riot이 안 따라잡은) 항목을
    /// 같은 팀 조합·비슷한 시각의 Leaguepedia 경기로 매칭해 스코어·상태만 교체한다.
    /// 팀 로고 등 나머지 메타데이터는 Riot 원본을 유지해 화면 표시 일관성을 지킨다.
    func reconcileResults(riotMatches: [Match], leaguepediaMatches: [Match]) -> [Match] {
        guard !leaguepediaMatches.isEmpty else { return riotMatches }
        let unstartedCutoff = Date().addingTimeInterval(-3 * 3600)
        let inProgressCutoff = Date().addingTimeInterval(-90 * 60)

        return riotMatches.map { riot in
            let isStaleUnstarted = riot.state == .unstarted && riot.startTime < unstartedCutoff
            let isZeroScoreCompleted = riot.state == .completed && riot.scoreA == 0 && riot.scoreB == 0
            let isStuckInProgress = riot.state == .inProgress && riot.startTime < inProgressCutoff
            guard isStaleUnstarted || isZeroScoreCompleted || isStuckInProgress else { return riot }
            guard let lp = leaguepediaMatches.first(where: { lp in
                lp.state == .completed &&
                sameTeams(riot, lp) &&
                abs(lp.startTime.timeIntervalSince(riot.startTime)) < 6 * 3600
            }) else {
                #if DEBUG
                reconcileLPLogger.debug("🔎 [Reconcile] \(riot.teamA.code) vs \(riot.teamB.code) — Leaguepedia \(leaguepediaMatches.count)건 중 매칭되는 completed 경기 없음")
                for lp in leaguepediaMatches where sameTeams(riot, lp) {
                    reconcileLPLogger.debug("🔎 [Reconcile]   팀은 일치하나 state=\(lp.state.rawValue) 또는 시간차 큼 (lp.startTime=\(lp.startTime.description))")
                }
                #endif
                return riot
            }

            let sameOrder = teamsMatch(riot.teamA, lp.teamA)
            let scoreA = sameOrder ? lp.scoreA : lp.scoreB
            let scoreB = sameOrder ? lp.scoreB : lp.scoreA

            return Match(id: riot.id, league: riot.league, teamA: riot.teamA, teamB: riot.teamB,
                         scoreA: scoreA, scoreB: scoreB, startTime: riot.startTime,
                         state: .completed, blockName: riot.blockName)
        }
    }

    /// Riot 라이브 스탯 피드가 멈춘 것으로 판단된 경기를 Leaguepedia와 대조.
    ///
    /// Leaguepedia의 MatchSchedule은 시리즈가 다 안 끝나도 Team1Score/Team2Score를 세트가
    /// 끝날 때마다 갱신해준다 (Winner만 시리즈 전체가 끝나야 채워짐) — 그래서 `.completed`뿐 아니라
    /// `.inProgress`(부분 스코어)도 받아들인다. 시리즈가 끝났으면 `.completed`인 Match를,
    /// 세트만 진행됐으면 `.inProgress`인 Match를 반환한다. 스코어가 전혀 없으면(0-0, 미시작) nil.
    func reconcileStuckLiveMatch(_ match: Match) async -> Match? {
        let lpMatches = await fetchLiveTournamentResults(for: match.league)
        guard let lp = lpMatches.first(where: { lp in
            (lp.state == .completed || lp.state == .inProgress) &&
            sameTeams(match, lp) &&
            abs(lp.startTime.timeIntervalSince(match.startTime)) < 6 * 3600
        }) else { return nil }

        let sameOrder = teamsMatch(match.teamA, lp.teamA)
        let scoreA = sameOrder ? lp.scoreA : lp.scoreB
        let scoreB = sameOrder ? lp.scoreB : lp.scoreA
        #if DEBUG
        reconcileLPLogger.debug("""
            🔁 [Reconcile] stuckLiveMatch \(match.teamA.code) vs \(match.teamB.code) — \
            lp.teamA=\(lp.teamA.name) lp.teamB=\(lp.teamB.name) sameOrder=\(sameOrder) \
            리보정전(\(match.scoreA)-\(match.scoreB)) → 리보정후(\(scoreA)-\(scoreB))
            """)
        #endif
        return Match(id: match.id, league: match.league, teamA: match.teamA, teamB: match.teamB,
                     scoreA: scoreA, scoreB: scoreB, startTime: match.startTime,
                     state: lp.state, blockName: match.blockName)
    }

    private func sameTeams(_ a: Match, _ b: Match) -> Bool {
        (teamsMatch(a.teamA, b.teamA) && teamsMatch(a.teamB, b.teamB)) ||
        (teamsMatch(a.teamA, b.teamB) && teamsMatch(a.teamB, b.teamA))
    }

    /// 이름이 정확히 같거나, 한쪽 이름이 다른 쪽에 포함되거나(예: "FURIA" ⊂ "FURIA ESPORTS"),
    /// Riot 팀 코드가 상대 이름과 겹치면 같은 팀으로 간주한다. Leaguepedia MatchSchedule의
    /// Team1/Team2는 위키 페이지명이라 Riot의 팀명과 완전히 일치하지 않는 경우가 있어 관대하게 비교한다.
    private func teamsMatch(_ a: Team, _ b: Team) -> Bool {
        let nameA = normalizedName(a)
        let nameB = normalizedName(b)
        if nameA == nameB || nameA.contains(nameB) || nameB.contains(nameA) { return true }

        let codeA = a.code.uppercased().trimmingCharacters(in: .whitespaces)
        let codeB = b.code.uppercased().trimmingCharacters(in: .whitespaces)
        if !codeA.isEmpty && (codeA == nameB || nameB.contains(codeA)) { return true }
        if !codeB.isEmpty && (codeB == nameA || nameA.contains(codeB)) { return true }
        return false
    }

    private func normalizedName(_ team: Team) -> String {
        team.name.uppercased().trimmingCharacters(in: .whitespaces)
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

        if leagueName == "Worlds" || leagueName == "MSI" || leagueName == "KeSPA Cup" {
            // 국제 대회 / 컵 대회: OverviewPage 이름 패턴 매칭이 Leagues 조인보다 안정적
            // (Leagues 테이블에 League_Short로 정식 등록 안 되어 있는 경우가 많음)
            let pattern = leagueName == "Worlds" ? "%Season World Championship%"
                : leagueName == "MSI"            ? "%Mid-Season Invitational%"
                : "%KeSPA Cup%"
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
            return LPTournamentEntry(page: page, year: year, dateStart: date)
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
            // Winner는 시리즈 전체가 끝나야 채워지지만, Team1Score/Team2Score는 시리즈 진행 중에도
            // 세트가 끝날 때마다 갱신된다 — Winner 없다고 무조건 unstarted로 취급하면 이미 나와 있는
            // 부분 스코어(예: 0-1)까지 통째로 버리게 되므로, 스코어가 있으면 진행 중으로 본다.
            let state: MatchState = !winner.isEmpty ? .completed : (scoreA > 0 || scoreB > 0 ? .inProgress : .unstarted)

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
