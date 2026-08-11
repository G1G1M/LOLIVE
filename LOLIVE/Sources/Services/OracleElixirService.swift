//
//  OracleElixirService.swift
//  LOLIVE
//
//  Oracle's Elixir(oe.datalisk.io — 과거 시즌 백필에도 쓰는 비공식 API)에서 선수 프로필
//  사진을 가져온다. Riot API는 은퇴/개편된 옛날 팀 선수를 아예 조회할 방법이 없고
//  (현재 로스터만 제공), 기존에 쓰던 Leaguepedia는 레이트리밋이 잦아(공식 문서 없음,
//  실측으로 자주 확인됨) 같은 API 키를 공유하는 이 엔드포인트로 교체했다.
//  키는 oracleselixir.com 프로덕션 JS 번들에 공개돼 있는 값(리버스 엔지니어링으로 확인,
//  historicalBackfill과 동일한 성격의 비공식 연동).
//

import Foundation

struct OracleElixirService: Sendable {

    static let shared = OracleElixirService()

    private let apiBase = "https://oe.datalisk.io"
    private let cdnBase = "https://cdn.datalisk.io"
    private let apiKey = "f561197a-82ea-4e54-acd2-386979018a7a"

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 10
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    private struct PlayerResponse: Decodable {
        let playerPhoto: String?
    }

    /// 선수 프로필 사진 URL 반환. 은퇴/현역 여부와 무관하게 조회 가능(실측 확인).
    func fetchPlayerImageURL(summonerName: String) async -> URL? {
        let cacheKey = CacheKey.oracleElixirPlayerImage(summonerName: summonerName)
        if let cached: String = AppDiskCache.get(cacheKey) {
            return cached.isEmpty ? nil : URL(string: cached)
        }

        guard let encoded = summonerName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(apiBase)/players/\(encoded)")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let player = try? JSONDecoder().decode(PlayerResponse.self, from: data),
              let photo = player.playerPhoto, !photo.isEmpty
        else {
            // 결과 없음도 캐싱해 불필요한 재요청 방지 (Leaguepedia 서비스와 동일한 패턴)
            AppDiskCache.set(cacheKey, value: "")
            return nil
        }

        let urlString = "\(cdnBase)/players/\(photo)"
        AppDiskCache.set(cacheKey, value: urlString)
        return URL(string: urlString)
    }

    // MARK: - 리그 공식 출전 선수 명단

    private struct TournamentsByLeagueEntry: Codable {
        let id: String
        let startDate: String
    }

    private struct TournamentPlayerRow: Decodable {
        let Player: String
    }

    /// Riot API 팀 로스터(조직 전체 인원 포함)를 "이번 시즌 실제 출전 선수"로 걸러낼 때 쓰는
    /// 기준 명단. 예전엔 Leaguepedia TournamentPlayers 테이블을 썼는데, 레이트리밋이 잦아서
    /// 리그당 요청 1번으로 끝나는 이 엔드포인트로 교체했다.
    func fetchOfficialPlayerNames(league: League) async -> Set<String>? {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return nil }

        guard let tournamentId = await currentTournamentId(oeLeagueName: oeLeagueName) else { return nil }

        let namesCacheKey = "oe_tournament_players_\(tournamentId)"
        if let cached: [String] = AppDiskCache.get(key: namesCacheKey, maxAge: 24 * 3600) {
            return Set(cached)
        }

        guard let encoded = tournamentId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(apiBase)/stats/players/byTournament?tournament=\(encoded)")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([TournamentPlayerRow].self, from: data)
        else { return nil }

        let names = Set(rows.map { $0.Player.lowercased() })
        guard !names.isEmpty else { return nil }
        AppDiskCache.set(key: namesCacheKey, value: Array(names))
        return names
    }

    /// 리그의 가장 최근(현재) 시즌 토너먼트 ID. `/tournaments/byLeague`가 리그당 시즌 목록을
    /// 최신순으로 주므로 첫 번째 항목을 쓴다. 응답 전체(~500KB)를 하루 캐싱해 리그별로 매번
    /// 다시 받지 않게 한다.
    private func currentTournamentId(oeLeagueName: String) async -> String? {
        let cacheKey = "oe_tournaments_by_league"
        let byLeague: [String: [TournamentsByLeagueEntry]]
        if let cached: [String: [TournamentsByLeagueEntry]] = AppDiskCache.get(key: cacheKey, maxAge: 24 * 3600) {
            byLeague = cached
        } else {
            guard let url = URL(string: "\(apiBase)/tournaments/byLeague") else { return nil }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            guard let (data, response) = try? await Self.session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode([String: [TournamentsByLeagueEntry]].self, from: data)
            else { return nil }
            byLeague = decoded
            AppDiskCache.set(key: cacheKey, value: byLeague)
        }
        guard let latest = byLeague[oeLeagueName]?.first else { return nil }
        // LCO/LLA처럼 최근 시즌 데이터가 아예 안 들어온 리그도 있다(리그 개편·중단 등).
        // 너무 오래된 시즌 명단으로 필터링하면 지금 선수단을 전부 걸러내버리는(=선수 0명)
        // 역효과가 나서, 1년 넘게 지난 데이터는 없는 것으로 취급하고 로스터 fallback에 맡긴다.
        guard let startDate = Self.oeDateFmt.date(from: latest.startDate),
              Date().timeIntervalSince(startDate) < 365 * 24 * 3600
        else { return nil }
        return latest.id
    }

    private static let oeDateFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - 리그 이름 매핑

    /// Riot API League → Oracle's Elixir 리그 이름(`/tournaments/byLeague`의 키) 변환.
    /// 지원하지 않는 리그는 nil 반환.
    static func oracleElixirLeagueName(for league: League) -> String? {
        let lower = league.name.lowercased().trimmingCharacters(in: .whitespaces)
        let slug  = league.slug.lowercased().trimmingCharacters(in: .whitespaces)
        switch true {
        case lower == "worlds" || slug == "worlds" ||
             lower.contains("world championship"):                      return "World Championship"
        case lower == "msi" || slug == "msi" ||
             lower.contains("mid-season"):                              return "Mid-Season Invitational"
        case lower == "lck" || slug == "lck":                         return "LoL Champions Korea"
        case lower.contains("챌린저스") && (lower.contains("lck") || slug.contains("lck")),
             lower.contains("challengers") && (lower.contains("lck") || slug.contains("lck")),
             lower == "lck cl", slug == "lck-cl", slug == "lck_cl",
             slug == "lck_challengers_league":                         return "LCK Challengers League"
        case lower == "lpl" || slug == "lpl":                         return "Tencent LoL Pro League"
        case (lower.contains("lpl") || slug.contains("lpl")) &&
             (lower.contains("dev") || lower.contains("ldl") ||
              slug.contains("dev") || slug.contains("ldl")):          return "LoL Development League"
        case lower == "lec" || slug == "lec",
             lower.contains("emea championship"):                      return "LoL EMEA Championship"
        case lower == "lcs" || slug == "lcs":                         return "League of Legends Championship Series"
        case (lower.contains("lcs") || slug.contains("lcs")) &&
             (lower.contains("acad") || slug.contains("acad")):       return "NA Academy League"
        case lower == "pcs" || slug == "pcs":                         return "Pacific Championship Series"
        case lower == "vcs" || slug == "vcs":                         return "Vietnam Championship Series"
        case lower == "cblol" || slug == "cblol":                     return "Circuit Brazilian League of Legends"
        case (lower.contains("cblol") || slug.contains("cblol")) &&
             (lower.contains("acad") || slug.contains("acad")):       return "Circuit Brazilian League of Legends Academy"
        case lower == "ljl" || slug == "ljl":                         return "LoL Japan League"
        case lower == "lco" || slug == "lco":                         return "LoL Circuit Oceania"
        case lower == "lla" || slug == "lla":                         return "Liga Latinoamerica"
        case lower == "lcp" || slug == "lcp":                         return "League of Legends Championship Pacific"
        case lower == "kespa cup" || slug == "kespa_cup" ||
             lower.contains("kespa"):                                  return "KeSPA Cup"
        default:                                                        return nil
        }
    }
}
