//
//  SharedDataService.swift
//  LOLIVEWidgets
//
//  App Groups UserDefaults에서 즐겨찾기 팀 데이터를 읽습니다.
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

    static func loadFavoriteTeams() -> [SharedFavoriteTeam] {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: favTeamsKey),
              let teams = try? JSONDecoder().decode([SharedFavoriteTeam].self, from: data)
        else { return [] }
        return teams
    }

    static func loadCurrentTeamIndex() -> Int {
        UserDefaults(suiteName: appGroupId)?.integer(forKey: "currentTeamIndex") ?? 0
    }

    static func saveCurrentTeamIndex(_ index: Int) {
        UserDefaults(suiteName: appGroupId)?.set(index, forKey: "currentTeamIndex")
    }

    static func loadTeamImageData(teamCode: String) -> Data? {
        let defaults = UserDefaults(suiteName: appGroupId)
        defaults?.synchronize()
        return defaults?.data(forKey: "teamImg_\(teamCode)")
    }

    // 메인 앱이 저장한 팀별 다음 경기 (MSI/Worlds 포함 전체 리그 커버)
    static func loadNextMatch(teamCode: String) -> SharedNextMatch? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: "nextMatches"),
              let matches = try? decoder.decode([String: SharedNextMatch].self, from: data)
        else { return nil }
        let match = matches[teamCode.uppercased()]
        // 1시간 이상 지난 캐시는 무시 (위젯 자체 API로 fallback)
        guard let match, Date().timeIntervalSince(match.savedAt) < 3600 else { return nil }
        return match
    }
}
