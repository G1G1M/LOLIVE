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
        defaults?.synchronize()  // 메인 앱이 쓴 최신 값을 강제로 읽어옴
        return defaults?.data(forKey: "teamImg_\(teamCode)")
    }
}
