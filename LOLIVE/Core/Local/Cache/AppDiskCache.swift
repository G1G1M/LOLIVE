//
//  AppDiskCache.swift
//  LOLIVE
//

import Foundation

struct AppDiskCache {

    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("riot_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct Envelope<T: Codable>: Codable {
        let value: T
        let savedAt: Date
    }

    /// 캐시에서 값을 읽습니다. maxAge 초 이내의 데이터만 반환하며, 만료된 파일은 자동 삭제합니다.
    static func get<T: Codable>(key: String, maxAge: TimeInterval) -> T? {
        let file = fileURL(for: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let envelope = try? decoder.decode(Envelope<T>.self, from: data) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        guard Date().timeIntervalSince(envelope.savedAt) < maxAge else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return envelope.value
    }

    /// API 실패 시 stale fallback용 — TTL 무시하고 캐시된 데이터를 그대로 반환합니다.
    static func getStale<T: Codable>(key: String) -> T? {
        let file = fileURL(for: key)
        guard let data = try? Data(contentsOf: file),
              let envelope = try? decoder.decode(Envelope<T>.self, from: data)
        else { return nil }
        return envelope.value
    }

    /// 값을 디스크에 저장합니다.
    static func set<T: Codable>(key: String, value: T) {
        let envelope = Envelope(value: value, savedAt: Date())
        guard let data = try? encoder.encode(envelope) else { return }
        try? data.write(to: fileURL(for: key), options: Data.WritingOptions.atomic)
    }

    /// 특정 키의 캐시를 삭제합니다.
    static func clear(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private static func fileURL(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent("\(safe).json")
    }
}

/// 여러 파일에서 같은 디스크 캐시를 참조하는 키/TTL을 한 곳에 모아둔 정의.
///
/// [왜 필요한가] RiotEsportsService가 캐시를 쓰고, 각 ViewModel의 preloadFromCache()가
/// 같은 캐시를 즉시 읽어 화면에 먼저 보여주는 패턴(README "ViewModel 선로딩 패턴")이라
/// 서비스 쪽 키/TTL과 ViewModel 쪽 키/TTL이 정확히 일치해야 한다. 이전엔 두 곳에 리터럴을
/// 각각 복사해서 썼는데, 여기 하나만 고치면 그걸 참조하는 모든 곳에 자동 반영된다.
enum CacheKey {
    case leagues
    case schedule(leagueId: String)
    case allSchedule(leagueId: String)
    case tournaments(leagueId: String)
    case standings(tournamentId: String)
    case roster(teamId: String)
    case live
    case oracleElixirPlayerImage(summonerName: String)
    /// 완료 경기 상세 — 여러 곳에서 같은 리터럴을 복사해 쓰던 걸 여기로 모았다.
    case eventDetail(matchId: String)
    /// Leaguepedia 밴 데이터 — 완료 경기는 변하지 않아 길게 잡는다.
    case leaguepediaBans(riotGameId: String)

    // Oracle's Elixir — 예전엔 OracleElixirService 안에 문자열 리터럴로 흩어져 있었다.
    // 키 문자열은 그때 쓰던 값 그대로라 기존에 쌓인 캐시가 그대로 유효하다.
    case oeTournamentsByLeague
    case oeTournamentPlayers(tournamentId: String)
    case oeTeamStats(tournamentId: String)
    case oePlayerStats(tournamentId: String)
    case oePlayerGameDetails(summonerName: String)
    case oeSingleMatch(riotMatchId: String)
    case oeDraft(gameId: String)

    var stringValue: String {
        switch self {
        case .leagues: return "leagues"
        case .schedule(let id): return "schedule_\(id)"
        case .allSchedule(let id): return "all_schedule_\(id)"
        case .tournaments(let id): return "tournaments_\(id)"
        case .standings(let id): return "standings_\(id)"
        case .roster(let id): return "roster_\(id)"
        case .live: return "live"
        case .oracleElixirPlayerImage(let name): return "oe_playerimg_\(name)"
        case .eventDetail(let id): return "event_detail_v2_\(id)"
        case .leaguepediaBans(let id): return "lp_bans_\(id)"
        case .oeTournamentsByLeague: return "oe_tournaments_by_league"
        case .oeTournamentPlayers(let id): return "oe_tournament_players_\(id)"
        case .oeTeamStats(let id): return "oe_team_stats_\(id)"
        case .oePlayerStats(let id): return "oe_player_stats_\(id)"
        case .oePlayerGameDetails(let name): return "oe_player_game_details_\(name)"
        case .oeSingleMatch(let id): return "oe_single_match_\(id)"
        case .oeDraft(let id): return "oe_draft_\(id)"
        }
    }

    var ttl: TimeInterval {
        switch self {
        case .leagues: return 24 * 3600
        case .schedule: return 15 * 60
        case .allSchedule: return 2 * 3600
        case .tournaments: return 24 * 3600
        case .standings: return 3600
        case .roster: return 12 * 3600
        case .live: return 5 * 60
        case .oracleElixirPlayerImage: return 7 * 24 * 3600
        case .eventDetail: return 30 * 24 * 3600
        case .leaguepediaBans: return 30 * 24 * 3600
        case .oeTournamentsByLeague: return 24 * 3600
        case .oeTournamentPlayers: return 24 * 3600
        case .oeTeamStats: return 24 * 3600
        case .oePlayerStats: return 24 * 3600
        case .oePlayerGameDetails: return 6 * 3600
        // 완료된 경기의 시리즈 구성/드래프트는 더 이상 바뀌지 않아 길게 잡는다.
        case .oeSingleMatch: return 30 * 24 * 3600
        case .oeDraft: return 30 * 24 * 3600
        }
    }
}

extension AppDiskCache {
    static func get<T: Codable>(_ key: CacheKey) -> T? { get(key: key.stringValue, maxAge: key.ttl) }
    static func getStale<T: Codable>(_ key: CacheKey) -> T? { getStale(key: key.stringValue) }
    static func set<T: Codable>(_ key: CacheKey, value: T) { set(key: key.stringValue, value: value) }
    static func clear(_ key: CacheKey) { clear(key: key.stringValue) }
}
