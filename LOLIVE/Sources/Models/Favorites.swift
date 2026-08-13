//
//  Favorites.swift
//  LOLIVE
//

import Foundation
import SwiftData

@Model
final class FavoriteTeam {
    var teamId: String
    var teamName: String
    var teamCode: String
    var teamImageURL: String?
    var leagueId: String
    var leagueName: String
    var leagueImageURL: String?
    var leagueRegion: String
    var addedAt: Date

    init(team: Team, league: League) {
        self.teamId = team.id
        self.teamName = team.name
        self.teamCode = team.code
        self.teamImageURL = team.imageURL
        self.leagueId = league.id
        self.leagueName = league.name
        self.leagueImageURL = league.imageURL
        self.leagueRegion = league.region
        self.addedAt = Date()
    }

    var asTeam: Team {
        Team(id: teamId, name: teamName, code: teamCode, imageURL: teamImageURL)
    }

    var asLeague: League {
        League(id: leagueId, slug: "", name: leagueName, region: leagueRegion, imageURL: leagueImageURL)
    }
}

/// 즐겨찾기 팀 하나를 (팀 ID, 팀 코드, 소속 리그 ID)로 요약한 값 — 여러 리그가 섞인 경기 목록에서
/// "이게 내가 즐겨찾기한 그 팀 맞나"를 판정할 때 쓴다.
///
/// 팀 ID만으로 비교하는 게 제일 안전하지만, Riot 일정 API가 팀 ID를 null로 주는 경우가 흔해서
/// 팀 코드 폴백이 필요하다(`RiotEsportsService.mapEventToMatch` 참고). 문제는 같은 조직의 1군/2군
/// 팀이 코드를 공유하는 경우가 있다는 것(예: "KT"가 LCK 본 리그와 LCK 챌린저스에 둘 다 있음, 팀
/// ID는 다름) — 코드만 보고 비교하면 2군 경기가 1군 즐겨찾기로 잘못 잡힌다(실측 확인: 위젯/Live
/// Activity가 KT 롤스터 대신 KT 챌린저스 경기를 보여줌). 그래서 코드 폴백은 반드시 같은 리그
/// 안에서만 허용한다 — `matches(team:league:)`를 항상 통해서 비교할 것.
struct FavoritedTeamRef: Hashable {
    let teamId: String
    let teamCode: String
    let leagueId: String

    static func matches(_ favorites: some Sequence<FavoritedTeamRef>, team: Team, league: League) -> Bool {
        favorites.contains {
            $0.teamId == team.id || ($0.teamCode == team.code && $0.leagueId == league.id)
        }
    }
}

@Model
final class FavoritePlayer {
    var playerId: String
    var summonerName: String
    var firstName: String?
    var lastName: String?
    var role: String
    var playerImageURL: String?
    var teamId: String
    var teamCode: String
    var leagueId: String
    var leagueName: String
    var leagueImageURL: String?
    var leagueRegion: String
    var addedAt: Date

    init(player: Player, league: League) {
        self.playerId = player.id
        self.summonerName = player.summonerName
        self.firstName = player.firstName
        self.lastName = player.lastName
        self.role = player.role
        self.playerImageURL = player.imageURL
        self.teamId = player.teamId
        self.teamCode = player.teamCode
        self.leagueId = league.id
        self.leagueName = league.name
        self.leagueImageURL = league.imageURL
        self.leagueRegion = league.region
        self.addedAt = Date()
    }

    var asPlayer: Player {
        Player(
            id: playerId,
            summonerName: summonerName,
            firstName: firstName,
            lastName: lastName,
            role: role,
            imageURL: playerImageURL,
            teamId: teamId,
            teamCode: teamCode
        )
    }

    var asLeague: League {
        League(id: leagueId, slug: "", name: leagueName, region: leagueRegion, imageURL: leagueImageURL)
    }
}
