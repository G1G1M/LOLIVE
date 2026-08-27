//
//  RiotEsportsService+Detail.swift
//  LOLIVE
//
//  일정·라이브 외의 부가 조회 — 대회 목록, 순위표, 팀 로스터, 경기 상세.
//

import Foundation

extension RiotEsportsService {

    func fetchTournaments(leagueId: String) async throws -> [Tournament] {
        let cacheKey = CacheKey.tournaments(leagueId: leagueId)
        if let cached: [Tournament] = AppDiskCache.get(cacheKey) { return cached }
        let query = [URLQueryItem(name: "leagueId", value: leagueId)]
        let data = try await request(path: "/getTournamentsForLeague", queryItems: query)
        let response = try decode(TournamentsResponse.self, from: data)
        let tournaments = response.data.leagues.flatMap { $0.tournaments }.map {
            Tournament(id: $0.id, slug: $0.slug, startDate: $0.startDate, endDate: $0.endDate ?? "")
        }
        AppDiskCache.set(cacheKey, value: tournaments)
        return tournaments
    }

    func fetchStandings(tournamentId: String) async throws -> [Standing] {
        let cacheKey = CacheKey.standings(tournamentId: tournamentId)
        if let cached: [Standing] = AppDiskCache.get(cacheKey) { return cached }
        let query = [URLQueryItem(name: "tournamentId", value: tournamentId)]
        let data = try await request(path: "/getStandings", queryItems: query)
        let response = try decode(StandingsResponse.self, from: data)
        let standingGroup = response.data.standings.first
        let stage = standingGroup?.stages.first { $0.type == "groups" }
                 ?? standingGroup?.stages.max(by: {
                     $0.sections.flatMap { $0.rankings }.count < $1.sections.flatMap { $0.rankings }.count
                 })
        let sections = stage?.sections ?? []
        var standings: [Standing] = []
        for section in sections {
            let groupName = section.name
            for ranking in section.rankings {
                for dto in ranking.teams {
                    let team = Team(id: dto.id, name: dto.name, code: dto.code, imageURL: https(dto.image))
                    let total = dto.record.wins + dto.record.losses
                    let winRate = total > 0 ? Double(dto.record.wins) / Double(total) : 0
                    var s = Standing(team: team, wins: dto.record.wins, losses: dto.record.losses,
                                     rank: ranking.ordinal, winRate: winRate)
                    s.group = groupName
                    standings.append(s)
                }
            }
        }
        standings = standings.sorted {
            if $0.group != $1.group { return Standing.groupSortKey($0.group) < Standing.groupSortKey($1.group) }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            return $0.team.name < $1.team.name
        }
        AppDiskCache.set(cacheKey, value: standings)
        return standings
    }

    func fetchTeamRoster(teamId: String) async throws -> [Player] {
        let cacheKey = CacheKey.roster(teamId: teamId)
        if let cached: [Player] = AppDiskCache.get(cacheKey) { return cached }
        let query = [URLQueryItem(name: "id", value: teamId)]
        let data = try await request(path: "/getTeams", queryItems: query)
        let response = try decode(TeamsResponse.self, from: data)
        guard let team = response.data.teams.first else { return [] }
        let players = (team.players ?? []).map { p in
            Player(id: p.id, summonerName: p.summonerName,
                   firstName: p.firstName, lastName: p.lastName,
                   role: p.role ?? "", imageURL: https(p.image),
                   teamId: team.id, teamCode: team.code)
        }
        AppDiskCache.set(cacheKey, value: players)
        return players
    }

    func fetchEventDetails(matchId: String) async throws -> EventDetailInfo {
        let query = [URLQueryItem(name: "id", value: matchId)]
        let data = try await request(path: "/getEventDetails", queryItems: query)
        let response = try decode(EventDetailsResponse.self, from: data)
        let matchDTO = response.data.event.match

        let games = matchDTO.games.map { game -> GameInfo in
            let blueTeamDTO = game.teams.first { $0.side == "blue" }
            let redTeamDTO  = game.teams.first { $0.side == "red"  }
            let state = GameInfoState(rawValue: game.state) ?? .unstarted
            let blueBans = blueTeamDTO?.bans?.map { $0.championId } ?? []
            let redBans  = redTeamDTO?.bans?.map  { $0.championId } ?? []
            let winnerTeamId = game.teams.first {
                $0.outcome == "win" || $0.result?.outcome == "win"
            }?.id
            return GameInfo(
                number: game.number, gameId: game.id, state: state,
                blueTeamId: blueTeamDTO?.id ?? "",
                redTeamId:  redTeamDTO?.id  ?? "",
                blueBans: blueBans,
                redBans:  redBans,
                winnerTeamId: winnerTeamId
            )
        }

        // MatchDetailDTO.teams 순서가 match.teamA, match.teamB 순서와 동일
        let teamAEsportsId = matchDTO.teams.first?.id ?? ""
        let teamBEsportsId = matchDTO.teams.dropFirst().first?.id ?? ""

        return EventDetailInfo(strategyCount: matchDTO.strategy.count, games: games,
                               teamAEsportsId: teamAEsportsId, teamBEsportsId: teamBEsportsId)
    }
}
