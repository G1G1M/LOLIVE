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
        League(id: leagueId, name: leagueName, region: leagueRegion, imageURL: leagueImageURL)
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
        League(id: leagueId, name: leagueName, region: leagueRegion, imageURL: leagueImageURL)
    }
}
