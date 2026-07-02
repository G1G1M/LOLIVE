//
//  SharedDataService.swift
//  LOLIVE
//
//  App Groups UserDefaults를 통해 위젯 Extension과 즐겨찾기 팀 데이터를 공유합니다.
//

import Foundation

struct SharedFavoriteTeam: Codable {
    let teamId: String
    let teamName: String
    let teamCode: String
    let teamImageURL: String?
    let leagueId: String
    let leagueName: String
    let leagueRegion: String
    let leagueImageURL: String?
}

struct SharedNextMatch: Codable {
    let opponentName: String
    let opponentCode: String
    let opponentImageURL: String?
    let startTime: Date
    let isLive: Bool
    let leagueName: String
    let savedAt: Date
}

enum SharedDataService {
    static let appGroupId = "group.lolive"
    private static let favTeamsKey = "sharedFavoriteTeams"

    static func saveTeamImageData(_ data: Data, teamCode: String) {
        let defaults = UserDefaults(suiteName: appGroupId)
        defaults?.set(data, forKey: "teamImg_\(teamCode)")
        defaults?.synchronize()  // 위젯 Extension이 즉시 읽을 수 있도록 강제 flush
    }

    static func loadTeamImageData(teamCode: String) -> Data? {
        UserDefaults(suiteName: appGroupId)?.data(forKey: "teamImg_\(teamCode)")
    }

    static func saveNextMatches(_ matches: [String: SharedNextMatch]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = try? encoder.encode(matches) else { return }
        defaults.set(data, forKey: "nextMatches")
        defaults.synchronize()
    }

    static func saveFavoriteTeams(_ teams: [FavoriteTeam]) {
        let shared = teams.map {
            SharedFavoriteTeam(
                teamId: $0.teamId,
                teamName: $0.teamName,
                teamCode: $0.teamCode,
                teamImageURL: $0.teamImageURL,
                leagueId: $0.leagueId,
                leagueName: $0.leagueName,
                leagueRegion: $0.leagueRegion,
                leagueImageURL: $0.leagueImageURL
            )
        }
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = try? JSONEncoder().encode(shared) else { return }
        defaults.set(data, forKey: favTeamsKey)
    }
}
