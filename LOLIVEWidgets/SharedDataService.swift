//
//  SharedDataService.swift
//  LOLIVEWidgets
//
//  App Groups UserDefaults에서 즐겨찾기 팀 데이터를 읽습니다.
//
//  ⚠️ 이 파일은 LOLIVE/Sources/Services/SharedDataService.swift와 물리적으로 복제되어 있습니다
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
    // 라이브 스코어 — 옵셔널로 두어 이전 버전이 저장한 데이터도 안전하게 디코딩
    let myScore: Int?
    let oppScore: Int?
    let currentGame: Int?
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

    /// 팀 코드 → SharedNextMatch 전체 스냅샷 로드 (즐겨찾기 여부 무관, 라이브 재사용용)
    static func loadAllNextMatches() -> [String: SharedNextMatch] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: "nextMatches"),
              let matches = try? decoder.decode([String: SharedNextMatch].self, from: data)
        else { return [:] }
        return matches
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
        guard let match else { return nil }
        // 예정 경기(시작 전)는 만료 없이 항상 유효 — 앱을 오래 안 열어도 위젯에 경기 정보 표시
        if match.startTime > Date() { return match }
        // 경기 시작 후에는 1시간 TTL (라이브 종료 감지)
        guard Date().timeIntervalSince(match.savedAt) < 3600 else { return nil }
        return match
    }

    /// "대표 팀"(즐겨찾기 화면에서 지정, 앱 틴트 컬러에도 씀) 코드 — Small 위젯이 캐러셀과
    /// 무관하게 항상 이 팀을 고정으로 보여줄 때 쓴다. `primaryTeamCode`가 App Group
    /// UserDefaults(`@AppStorage(store:)`)에 저장되므로 여기선 읽기만 한다.
    static func loadPrimaryTeamCode() -> String? {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let code = defaults.string(forKey: "primaryTeamCode"), !code.isEmpty
        else { return nil }
        return code
    }
}
