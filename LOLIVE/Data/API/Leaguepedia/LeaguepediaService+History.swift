//
//  LeaguepediaService+History.swift
//  LOLIVE
//
//  Worlds / MSI 등 과거 대회 및 리그 히스토리 경기 데이터를 담당하는 Extension.
//
//  [설계 원칙]
//  - Riot API는 ~1년 이내 경기만 제공 → 그 이전 데이터는 서버(Firestore, 백필된 Leaguepedia
//    데이터)의 getHistoricalYears/getHistoricalMatches Callable로 조회한다(FirebaseHistoricalService).
//    이 파일은 더 이상 연도별 과거 경기 목록을 직접 Leaguepedia에서 실시간 조회하지 않는다 —
//    예전엔 여기서 직접 했었지만(historicalYears/fetchMatches(for:year:) 등), 레이트리밋 때문에
//    Worlds/MSI처럼 연도가 많은 대회에서 느리거나 자주 막혀서 서버 경로로 전환함(2026-08-07).
//  - 이 파일에 남은 건 서버가 못 채워주는 "진행 중인 대회의 실시간 결과 보완"(케스파컵 등,
//    아래 fetchLiveTournamentResults/reconcileResults/reconcileStuckLiveMatch)뿐이다.
//

import Foundation
import os

private let reconcileLPLogger = Logger(subsystem: "com.lolive", category: "Reconcile")

extension LeaguepediaService {

    // MARK: - 내부 헬퍼

    /// 대회 페이지 목록을 캐시에서 읽거나 API로 가져오는 공통 경로.
    func cachedOrFetchPages(leagueName: String) async -> [LPTournamentEntry] {
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
    func matchesForOverviewPage(_ overviewPage: String, league: League) async -> [Match] {
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

    /// 중복 Match 제거 (동일 id 유지, 첫 번째 등장 우선).
    func deduplicated(_ matches: [Match]) -> [Match] {
        var seen = Set<String>()
        return matches.filter { seen.insert($0.id).inserted }
    }
}
