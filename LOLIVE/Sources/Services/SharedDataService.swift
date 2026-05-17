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

enum SharedDataService {
    static let appGroupId = "group.lolive"
    private static let favTeamsKey = "sharedFavoriteTeams"

    static func saveTeamImageData(_ data: Data, teamCode: String) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return }
        let url = container.appendingPathComponent("teamImg_\(teamCode).dat")
        try? data.write(to: url, options: .atomic)
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
