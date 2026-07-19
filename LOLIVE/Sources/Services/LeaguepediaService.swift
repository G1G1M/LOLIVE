//
//  LeaguepediaService.swift
//  LOLIVE
//
//  Leaguepedia MediaWiki Cargo API 클라이언트의 핵심 레이어.
//
//  [파일 구조]
//  이 파일은 공통 네트워크 인프라와 리그 이름 매핑만 담당한다.
//  기능별 Extension은 아래 파일에 분리되어 있다:
//    - LeaguepediaService+Stats.swift    선수 스탯 / 챔피언픽 / 밴 / 이미지
//    - LeaguepediaService+History.swift  과거 경기 데이터 (Worlds/MSI/리그 히스토리)
//
//  [공유 타입]
//    - LeaguepediaCargo.swift  CargoResp · CargoRow · LPTournamentEntry · BansCacheEntry
//    - LeaguepediaCache.swift  actor LeaguepediaCache (메모리 + 디스크 캐시)
//
//  [Rate Limit]
//  모든 Leaguepedia 요청은 LeaguepediaRateLimiter를 통해 0.5초 간격으로 직렬화된다.
//  foreground / background에서 동시에 호출해도 단일 actor가 큐를 관리한다.
//

import Foundation

// MARK: - Service

struct LeaguepediaService: Sendable {

    static let shared = LeaguepediaService()

    /// Leaguepedia MediaWiki API 엔드포인트
    let baseURL = "https://lol.fandom.com/api.php"

    /// 공유 URLSession (타임아웃: 요청 15초, 리소스 60초)
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 15
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    /// UTC 기준 날짜 파서 — Leaguepedia DateTime_UTC 컬럼 형식("yyyy-MM-dd HH:mm:ss")
    static let utcDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - OverviewPage 조회

    /// 해당 리그의 현재(또는 가장 최근) OverviewPage 반환.
    /// 메모리/디스크 캐시 히트 시 API 호출 없이 즉시 반환.
    func currentOverviewPage(leagueName: String) async -> String? {
        if let cached = await LeaguepediaCache.shared.overviewPage(for: leagueName) { return cached }
        return await candidateOverviewPages(leagueName: leagueName).first
    }

    /// 최근 OverviewPage 후보 목록 반환 (최신 → 오래된 순, 최대 3개).
    ///
    /// [정렬 기준]
    /// 종료일이 없는(진행 중이거나 예정된) 토너먼트를 먼저,
    /// 이미 종료된 토너먼트를 그 다음에 반환한다.
    func candidateOverviewPages(leagueName: String) async -> [String] {
        if let cached = await LeaguepediaCache.shared.candidatePages(for: leagueName) { return cached }

        var c = URLComponents(string: baseURL)!
        c.queryItems = [
            .init(name: "action",   value: "cargoquery"),
            .init(name: "tables",   value: "Tournaments,Leagues"),
            .init(name: "join_on",  value: "Tournaments.League=Leagues.League"),
            .init(name: "fields",   value: "Tournaments.OverviewPage,Tournaments.DateStart,Tournaments.Date"),
            .init(name: "where",    value: "Leagues.League_Short='\(escapeSql(leagueName))'"),
            .init(name: "order_by", value: "Tournaments.DateStart DESC"),
            .init(name: "limit",    value: "6"),
            .init(name: "format",   value: "json"),
        ]
        guard let url = c.url,
              let data = await cargoData(url: url),
              let resp = try? JSONDecoder().decode(CargoResp.self, from: data) else { return [] }

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        var active: [String] = []  // 진행 중 또는 예정
        var past:   [String] = []  // 이미 종료

        for row in resp.cargoquery {
            guard let page  = row.title["OverviewPage"],
                  let start = row.title["DateStart"].flatMap({ fmt.date(from: $0) }),
                  start <= now else { continue }
            if let endStr = row.title["Date"], !endStr.isEmpty,
               let end = fmt.date(from: endStr), now > end {
                past.append(page)
            } else {
                active.append(page)
            }
        }

        let result = Array((active + past).prefix(3))
        if let first = result.first {
            await LeaguepediaCache.shared.setOverviewPage(first, for: leagueName)
        }
        await LeaguepediaCache.shared.setCandidatePages(result, for: leagueName)
        return result
    }

    // MARK: - 리그 이름 매핑

    /// Riot API / PandaScore League → Leaguepedia League_Short 변환.
    /// Leaguepedia Cargo API의 `where` 절에 사용할 이름을 반환.
    /// 지원하지 않는 리그는 nil 반환 → 호출부에서 guard 처리.
    func leaguepediaName(for league: League) -> String? {
        let lower = league.name.lowercased().trimmingCharacters(in: .whitespaces)
        let slug  = league.slug.lowercased().trimmingCharacters(in: .whitespaces)
        switch true {
        case lower == "worlds" || slug == "worlds" ||
             lower.contains("world championship"):                      return "Worlds"
        case lower == "msi" || slug == "msi" ||
             lower.contains("mid-season"):                              return "MSI"
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

    // MARK: - 네트워크

    /// Cargo API URL을 호출하고 Data를 반환.
    ///
    /// Rate limit 응답(429/"ratelimited") 발생 시 Retry-After 헤더(없으면 12초) 후 최대 3회 재시도.
    /// Task가 취소되면 즉시 nil 반환.
    func cargoData(url: URL) async -> Data? {
        await LeaguepediaRateLimiter.shared.claimSlot()
        guard !Task.isCancelled else { return nil }

        var request = URLRequest(url: url)
        request.setValue("LOLIVE/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            var (data, response) = try await Self.session.data(for: request)
            var retries = 0
            while isRateLimited(data) && retries < 3 {
                let http = response as? HTTPURLResponse
                let wait = http?.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? 12.0
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return nil }
                await LeaguepediaRateLimiter.shared.claimSlot()
                guard !Task.isCancelled else { return nil }
                (data, response) = try await Self.session.data(for: request)
                retries += 1
            }
            return isRateLimited(data) ? nil : data
        } catch {
            return nil
        }
    }

    // MARK: - 유틸리티

    /// Cargo API 응답에서 rate limit 에러 여부 확인.
    func isRateLimited(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err  = json["error"] as? [String: Any],
              let code = err["code"] as? String
        else { return false }
        return code == "ratelimited"
    }

    /// SQL 인젝션 방지를 위한 단따옴표 이스케이프.
    func escapeSql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }

    /// Leaguepedia 콤마 구분 밴 문자열 → [String] 배열 파싱.
    /// 예: "Orianna,Azir,Jayce" → ["Orianna", "Azir", "Jayce"]
    func parseBans(_ str: String) -> [String] {
        str.split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Rate Limiter

/// 모든 Leaguepedia API 요청을 단일 큐로 직렬화하는 Rate Limiter.
///
/// foreground / background Task가 동시에 cargoData를 호출해도 이 actor가
/// 0.5초 간격을 보장하므로 서버 측 rate limit(초당 2 req)을 넘지 않는다.
actor LeaguepediaRateLimiter {
    static let shared = LeaguepediaRateLimiter(interval: 0.5)

    private var nextSlotTime = Date.distantPast
    private let slotInterval: TimeInterval

    init(interval: TimeInterval) { slotInterval = interval }

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
