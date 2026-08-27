//
//  LeaguepediaCache+Disk.swift
//  LOLIVE
//
//  디스크 캐시 파일 경로 규칙과, 저장할 때 쓰는 Codable 래퍼 타입.
//  전부 LeaguepediaCache 안에 중첩돼 있어 이름이 밖으로 새지 않는다.
//

import Foundation

extension LeaguepediaCache {

    // MARK: - 디스크 파일 경로 헬퍼

    static let overviewPagesDiskFile =
        cacheDir.appendingPathComponent("overview_pages.json")

    static func cacheFile(for page: String) -> URL {
        let safe = page.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }

    static func champCacheFile(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("champs_\(safe).json")
    }

    static func champBatchFile(for page: String) -> URL {
        let safe = page
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("champ_batch_\(safe).json")
    }

    static func playerNamesFile(for leagueName: String) -> URL {
        let safe = leagueName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("playernames_\(safe).json")
    }

    static func historicalFile(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }

    static func tournamentPagesFile(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("ovpages_\(safe).json")
    }

    // MARK: - 디스크 래퍼 타입 (Codable 직렬화용)

    struct DiskWrapper: Codable {
        let savedAt: Date
        let stats: [String: PlayerSeasonStats]
    }

    struct ChampPicksDiskWrapper: Codable {
        let savedAt: Date
        let picks: [ChampionPickEntry]
    }

    struct ChampBatchDiskWrapper: Codable {
        let savedAt: Date
        let picks: [String: [ChampionPickEntry]]
    }

    struct HistMatchesWrapper: Codable {
        let savedAt: Date
        let matches: [Match]
    }

    struct TournamentPagesWrapper: Codable {
        let savedAt: Date
        let entries: [LPTournamentEntry]
    }

    struct PlayerNamesDiskWrapper: Codable {
        let savedAt: Date
        let names: Set<String>
    }

    struct OverviewPagesDiskWrapper: Codable {
        let savedAt: Date
        let pages: [String: String]
    }
}
