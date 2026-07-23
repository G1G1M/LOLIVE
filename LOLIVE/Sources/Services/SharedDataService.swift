//
//  SharedDataService.swift
//  LOLIVE
//
//  App Groups UserDefaults를 통해 위젯 Extension과 즐겨찾기 팀 데이터를 공유합니다.
//
//  ⚠️ 이 파일은 LOLIVEWidgets/SharedDataService.swift와 물리적으로 복제되어 있습니다
//  (앱 타겟과 위젯 Extension 타겟이 코드를 공유할 SPM 모듈이 없어서 파일을 그대로 복사함).
//  구조체(SharedFavoriteTeam/SharedNextMatch)나 UserDefaults 키를 바꿀 땐 반드시 두 파일을 함께 수정하세요.

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
