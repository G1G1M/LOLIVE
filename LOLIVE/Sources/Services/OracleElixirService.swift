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

/// 시즌/구간 선택 칩에 쓰는 값 — `OracleElixirService.availableSeasons(league:)` 참고.
struct OESeasonOption: Identifiable, Hashable {
    let id: String
    let name: String
}

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
        let name: String
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

    // MARK: - 팀 시즌 스탯

    /// `/stats/teams/byTournament` 원본 행 — 필드명은 OE 표기 그대로(AGT=평균 게임 시간(분),
    /// FB%=퍼스트블러드율, DRG%=드래곤 획득률, BN%=바론 획득률, GD15=15분 골드 격차, 그 외 확장
    /// 필드는 `TeamSeasonStats` 정의부 주석 참고). `%` 필드는 팀에 따라 `null`이 오기도 해서
    /// (예: 장로 드래곤이 안 나온 시즌의 ELD%) 전부 옵셔널 raw 문자열로 받고 변환한다.
    private struct TeamStatsRow: Codable {
        let Team: String
        let GP: Int
        let W: Int
        let L: Int
        let AGT: Double
        let K: Int
        let D: Int
        let KD: Double
        let CKPM: Double
        let GPR: Double
        let EGR: Double
        let MLR: Double
        let GD15: Double?
        let PPG: Double
        let WPM: Double
        let CWPM: Double
        let WCPM: Double
        private let gspdRaw: String?
        private let firstBloodRateRaw: String?
        private let firstTowerRateRaw: String?
        private let firstToThreeTowersRateRaw: String?
        private let heraldRateRaw: String?
        private let voidGrubsRateRaw: String?
        private let firstDragonRateRaw: String?
        private let dragonRateRaw: String?
        private let elderDragonRateRaw: String?
        private let firstBaronRateRaw: String?
        private let baronRateRaw: String?
        private let laneCsShareRaw: String?
        private let jungleCsShareRaw: String?

        enum CodingKeys: String, CodingKey {
            case Team, GP, W, L, AGT, K, D, KD, CKPM, GPR, EGR, MLR, GD15, PPG, WPM, CWPM, WCPM
            case gspdRaw = "GSPD"
            case firstBloodRateRaw = "FB%"
            case firstTowerRateRaw = "FT%"
            case firstToThreeTowersRateRaw = "F3T%"
            case heraldRateRaw = "HLD%"
            case voidGrubsRateRaw = "GRB%"
            case firstDragonRateRaw = "FD%"
            case dragonRateRaw = "DRG%"
            case elderDragonRateRaw = "ELD%"
            case firstBaronRateRaw = "FBN%"
            case baronRateRaw = "BN%"
            case laneCsShareRaw = "LNE%"
            case jungleCsShareRaw = "JNG%"
        }

        var killDeathRatio: Double { KD }
        var goldSpentPercentDiff: Double { Self.percent(gspdRaw) ?? 0 }
        var firstBloodRate: Double { Self.percent(firstBloodRateRaw) ?? 0 }
        var firstTowerRate: Double { Self.percent(firstTowerRateRaw) ?? 0 }
        var firstToThreeTowersRate: Double { Self.percent(firstToThreeTowersRateRaw) ?? 0 }
        var heraldRate: Double { Self.percent(heraldRateRaw) ?? 0 }
        var voidGrubsRate: Double { Self.percent(voidGrubsRateRaw) ?? 0 }
        var firstDragonRate: Double { Self.percent(firstDragonRateRaw) ?? 0 }
        var dragonRate: Double { Self.percent(dragonRateRaw) ?? 0 }
        var elderDragonRate: Double? { Self.percent(elderDragonRateRaw) }
        var firstBaronRate: Double { Self.percent(firstBaronRateRaw) ?? 0 }
        var baronRate: Double { Self.percent(baronRateRaw) ?? 0 }
        var laneCsShare: Double { Self.percent(laneCsShareRaw) ?? 0 }
        var jungleCsShare: Double { Self.percent(jungleCsShareRaw) ?? 0 }

        private static func percent(_ raw: String?) -> Double? {
            guard let raw, let value = Double(raw.replacingOccurrences(of: "%", with: ""))
            else { return nil }
            return value / 100
        }
    }

    /// 팀 단위 시즌 집계 스탯. 리그당 요청 1번(팀 전체 목록)으로 끝나고 결과는 24시간 캐싱 —
    /// `fetchOfficialPlayerNames`와 같은 tournamentId 해석 경로를 재사용한다.
    /// `tournamentId`를 명시하면(시즌 선택 칩) 그 시즌으로, 안 주면 현재 시즌으로 조회한다.
    func fetchTeamStats(team: Team, league: League, tournamentId explicitTournamentId: String? = nil) async -> TeamSeasonStats? {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return nil }
        guard let tournamentId = await resolveTournamentId(explicit: explicitTournamentId, oeLeagueName: oeLeagueName)
        else { return nil }

        let cacheKey = "oe_team_stats_\(tournamentId)"
        let rows: [TeamStatsRow]
        if let cached: [TeamStatsRow] = AppDiskCache.get(key: cacheKey, maxAge: 24 * 3600) {
            rows = cached
        } else {
            guard let encoded = tournamentId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(apiBase)/stats/teams/byTournament?tournament=\(encoded)")
            else { return nil }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            guard let (data, response) = try? await Self.session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode([TeamStatsRow].self, from: data)
            else { return nil }
            rows = decoded
            AppDiskCache.set(key: cacheKey, value: rows)
        }

        guard let row = Self.matchByName(rows, target: team.name, key: { $0.Team })
        else { return nil }

        return TeamSeasonStats(
            games: row.GP, wins: row.W, losses: row.L,
            avgGameMinutes: row.AGT,
            firstBloodRate: row.firstBloodRate,
            dragonRate: row.dragonRate,
            baronRate: row.baronRate,
            goldDiffAt15: row.GD15 ?? 0,
            kills: row.K, deaths: row.D,
            killDeathRatio: row.killDeathRatio,
            combinedKillsPerMinute: row.CKPM,
            goldPercentRating: row.GPR,
            goldSpentPercentDiff: row.goldSpentPercentDiff,
            earlyGameRating: row.EGR,
            midLateRating: row.MLR,
            firstTowerRate: row.firstTowerRate,
            firstToThreeTowersRate: row.firstToThreeTowersRate,
            platesPerGame: row.PPG,
            heraldRate: row.heraldRate,
            voidGrubsRate: row.voidGrubsRate,
            firstDragonRate: row.firstDragonRate,
            elderDragonRate: row.elderDragonRate,
            firstBaronRate: row.firstBaronRate,
            laneCsShare: row.laneCsShare,
            jungleCsShare: row.jungleCsShare,
            wardsPerMinute: row.WPM,
            controlWardsPerMinute: row.CWPM,
            wardsClearedPerMinute: row.WCPM
        )
    }

    /// Riot API와 OE는 서로 다른 소스라 이름 표기가 어긋나는 경우가 있다(실측 확인:
    /// 팀 "Gen.G Esports" ↔ "Gen.G", "NONGSHIM RED FORCE" ↔ "Nongshim RedForce"처럼
    /// 접미사·띄어쓰기 차이 — 선수 이름도 같은 종류의 표기 드리프트가 있을 수 있어 공용으로 씀).
    /// 단순 대소문자 무시 비교로는 통째로 매칭 실패할 수 있어, 영숫자만 남기고 정규화한 뒤
    /// 완전일치 → (그래도 안 맞으면) 부분일치 순으로 매칭한다.
    private static func matchByName<Row>(_ rows: [Row], target name: String, key: (Row) -> String) -> Row? {
        let target = normalizedName(name)
        guard !target.isEmpty else { return nil }

        if let exact = rows.first(where: { normalizedName(key($0)) == target }) {
            return exact
        }
        // 부분일치는 접미사가 붙은 경우 대응 — 너무 짧은 이름끼리 우연히 겹치는 걸 막기 위해
        // 최소 길이를 둔다.
        guard target.count >= 4 else { return nil }
        return rows.first { row in
            let candidate = normalizedName(key(row))
            guard candidate.count >= 4 else { return false }
            return candidate.contains(target) || target.contains(candidate)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - 선수 시즌 스탯

    /// `/stats/players/byTournament` 원본 행 — 필드명은 OE 표기 그대로. `CTR%`는 정확한 정의를
    /// 못 찾아서(oracleselixir.com 자체 정의 페이지가 접근 차단됨) 의도적으로 안 씀 — 뜻이
    /// 불확실한 필드를 추측해서 라벨 붙이지 말 것.
    private struct PlayerStatsRow: Codable {
        let Player: String
        let Team: String
        let GP: Int
        let K: Int
        let D: Int
        let A: Int
        let KDA: Double
        let GD10: Double?
        let XPD10: Double?
        let CSD10: Double?
        let CSPM: Double
        let DPM: Double
        let TDPG: Double
        let EGPM: Double
        let STL: Int
        let WPM: Double
        let CWPM: Double
        let WCPM: Double
        private let winRateRaw: String?
        private let killParticipationRaw: String?
        private let killShareRaw: String?
        private let deathShareRaw: String?
        private let firstBloodRateRaw: String?
        private let csShareAt15Raw: String?
        private let damageShareRaw: String?
        private let damageShareAt15Raw: String?
        private let goldShareRaw: String?

        enum CodingKeys: String, CodingKey {
            case Player, Team, GP, K, D, A, KDA, GD10, XPD10, CSD10, CSPM, DPM, TDPG, EGPM, STL, WPM, CWPM, WCPM
            case winRateRaw = "W%"
            case killParticipationRaw = "KP"
            case killShareRaw = "KS%"
            case deathShareRaw = "DTH%"
            case firstBloodRateRaw = "FB%"
            case csShareAt15Raw = "CS%P15"
            case damageShareRaw = "DMG%"
            case damageShareAt15Raw = "D%P15"
            case goldShareRaw = "GOLD%"
        }

        var winRate: Double { Self.percent(winRateRaw) ?? 0 }
        var killParticipation: Double { Self.percent(killParticipationRaw) ?? 0 }
        var killShare: Double { Self.percent(killShareRaw) ?? 0 }
        var deathShare: Double { Self.percent(deathShareRaw) ?? 0 }
        var firstBloodRate: Double { Self.percent(firstBloodRateRaw) ?? 0 }
        var csShareAt15: Double { Self.percent(csShareAt15Raw) ?? 0 }
        var damageShare: Double { Self.percent(damageShareRaw) ?? 0 }
        var damageShareAt15: Double { Self.percent(damageShareAt15Raw) ?? 0 }
        var goldShare: Double { Self.percent(goldShareRaw) ?? 0 }

        private static func percent(_ raw: String?) -> Double? {
            guard let raw, let value = Double(raw.replacingOccurrences(of: "%", with: ""))
            else { return nil }
            return value / 100
        }
    }

    /// 선수 단위 시즌 집계 스탯. 리그당 요청 1번(선수 전체 목록)으로 끝나고 결과는 24시간
    /// 캐싱 — `fetchTeamStats`와 같은 tournamentId 해석 경로를 재사용한다. 이름 매칭은
    /// `player.summonerName`이 OE `Player` 필드와 표기가 다를 수 있어(대소문자·공백 등)
    /// `matchByName`으로 처리한다.
    /// `tournamentId`를 명시하면(시즌 선택 칩) 그 시즌으로, 안 주면 현재 시즌으로 조회한다.
    func fetchPlayerStats(player: Player, league: League, tournamentId explicitTournamentId: String? = nil) async -> PlayerOEStats? {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return nil }
        guard let tournamentId = await resolveTournamentId(explicit: explicitTournamentId, oeLeagueName: oeLeagueName)
        else { return nil }

        let cacheKey = "oe_player_stats_\(tournamentId)"
        let rows: [PlayerStatsRow]
        if let cached: [PlayerStatsRow] = AppDiskCache.get(key: cacheKey, maxAge: 24 * 3600) {
            rows = cached
        } else {
            guard let encoded = tournamentId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(apiBase)/stats/players/byTournament?tournament=\(encoded)")
            else { return nil }
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            guard let (data, response) = try? await Self.session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode([PlayerStatsRow].self, from: data)
            else { return nil }
            rows = decoded
            AppDiskCache.set(key: cacheKey, value: rows)
        }

        guard let row = Self.matchByName(rows, target: player.summonerName, key: { $0.Player })
        else { return nil }

        return PlayerOEStats(
            games: row.GP, winRate: row.winRate,
            kills: row.K, deaths: row.D, assists: row.A, kda: row.KDA,
            killParticipation: row.killParticipation,
            killShare: row.killShare,
            deathShare: row.deathShare,
            firstBloodRate: row.firstBloodRate,
            goldDiffAt10: row.GD10, xpDiffAt10: row.XPD10, csDiffAt10: row.CSD10,
            csPerMin: row.CSPM,
            csShareAt15: row.csShareAt15,
            damagePerMin: row.DPM,
            damageShare: row.damageShare,
            damageShareAt15: row.damageShareAt15,
            totalDamagePerGame: row.TDPG,
            earnedGoldPerMin: row.EGPM,
            goldShare: row.goldShare,
            steals: row.STL,
            wardsPerMinute: row.WPM,
            controlWardsPerMinute: row.CWPM,
            wardsClearedPerMinute: row.WCPM
        )
    }

    /// `/tournaments/byLeague` 전체 응답(리그당 시즌 목록, 최신순). 응답 전체(~500KB)를
    /// 하루 캐싱해 리그별로 매번 다시 받지 않게 한다. `currentTournamentId`/`availableSeasons`가
    /// 공유하는 내부 헬퍼.
    private func tournamentsByLeague() async -> [String: [TournamentsByLeagueEntry]] {
        let cacheKey = "oe_tournaments_by_league"
        if let cached: [String: [TournamentsByLeagueEntry]] = AppDiskCache.get(key: cacheKey, maxAge: 24 * 3600) {
            return cached
        }
        guard let url = URL(string: "\(apiBase)/tournaments/byLeague") else { return [:] }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode([String: [TournamentsByLeagueEntry]].self, from: data)
        else { return [:] }
        AppDiskCache.set(key: cacheKey, value: decoded)
        return decoded
    }

    /// `fetchTeamStats`/`fetchPlayerStats`가 공유하는 tournamentId 결정 로직 — 명시적으로
    /// 넘어온 시즌(칩 선택)이 있으면 그걸, 없으면 현재 시즌을 쓴다.
    private func resolveTournamentId(explicit: String?, oeLeagueName: String) async -> String? {
        if let explicit { return explicit }
        return await currentTournamentId(oeLeagueName: oeLeagueName)
    }

    /// 리그의 가장 최근(현재) 시즌 토너먼트 ID — 시즌 목록의 첫 번째 항목.
    private func currentTournamentId(oeLeagueName: String) async -> String? {
        guard let latest = await tournamentsByLeague()[oeLeagueName]?.first else { return nil }
        // LCO/LLA처럼 최근 시즌 데이터가 아예 안 들어온 리그도 있다(리그 개편·중단 등).
        // 너무 오래된 시즌 명단으로 필터링하면 지금 선수단을 전부 걸러내버리는(=선수 0명)
        // 역효과가 나서, 1년 넘게 지난 데이터는 없는 것으로 취급하고 로스터 fallback에 맡긴다.
        guard let startDate = Self.oeDateFmt.date(from: latest.startDate),
              Date().timeIntervalSince(startDate) < 365 * 24 * 3600
        else { return nil }
        return latest.id
    }

    /// "현재 시즌" 안의 라운드/구간 목록(예: LCK "2026 Rounds 3-4"/"2026 Road to MSI"/
    /// "2026 Rounds 1-2"/"2026 Cup"). 토너먼트 id가 "리그/연도 Season/구간" 형식이라
    /// (실측 확인: "LCK/2026 Season/Rounds 3-4"), 최신 항목과 접두사("LCK/2026 Season/")가
    /// 같은 것만 추려서 "지난 시즌"은 자동으로 빠진다. 목록은 이미 최신순이라 정렬 그대로 유지.
    func availableSeasons(league: League) async -> [OESeasonOption] {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return [] }
        guard let entries = await tournamentsByLeague()[oeLeagueName], let latest = entries.first else { return [] }
        guard let prefix = Self.seasonPrefix(of: latest.id) else {
            return [OESeasonOption(id: latest.id, name: latest.name)]
        }
        return entries
            .filter { $0.id.hasPrefix(prefix) }
            .map { OESeasonOption(id: $0.id, name: $0.name) }
    }

    /// "LCK/2026 Season/Rounds 3-4" → "LCK/2026 Season/" (마지막 "/" 앞까지).
    private static func seasonPrefix(of tournamentId: String) -> String? {
        guard let lastSlash = tournamentId.range(of: "/", options: .backwards) else { return nil }
        return String(tournamentId[..<lastSlash.upperBound])
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
