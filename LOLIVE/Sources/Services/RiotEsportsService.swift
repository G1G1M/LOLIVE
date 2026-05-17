//
//  RiotEsportsService.swift
//  LOLIVE
//

import Foundation

// MARK: - APIError

enum APIError: Error {
    case invalidURL
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
    case unknown(Error)
}

// MARK: - Protocol

protocol RiotEsportsServiceProtocol: Sendable {
    func fetchLeagues() async throws -> [League]
    func fetchSchedule(league: League) async throws -> [Match]
    func fetchLive() async throws -> [LiveMatch]
    func fetchEventDetails(matchId: String) async throws -> EventDetailInfo
    func fetchTournaments(leagueId: String) async throws -> [Tournament]
    func fetchStandings(tournamentId: String) async throws -> [Standing]
    func fetchTeamRoster(teamId: String) async throws -> [Player]
}

// MARK: - Service

final class RiotEsportsService: RiotEsportsServiceProtocol {

    private let baseURL = "https://esports-api.lolesports.com/persisted/gw"
    private let apiKey  = APIKeys.riotApiKey

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Public

    func fetchLeagues() async throws -> [League] {
        let data = try await request(path: "/getLeagues", queryItems: [])
        let response = try decode(LeaguesResponse.self, from: data)
        return response.data.leagues.map {
            League(id: $0.id, name: $0.name, region: $0.region, imageURL: https($0.image))
        }
    }

    func fetchSchedule(league: League) async throws -> [Match] {
        let query = [URLQueryItem(name: "leagueId", value: league.id)]
        let data = try await request(path: "/getSchedule", queryItems: query)
        let response = try decode(ScheduleResponse.self, from: data)
        return response.data.schedule.events.compactMap { mapEventToMatch($0, fallbackLeague: league) }
    }

    func fetchLive() async throws -> [LiveMatch] {
        let data = try await request(path: "/getLive", queryItems: [])
        let response = try decode(LiveResponse.self, from: data)
        return response.data.schedule.events.compactMap { event in
            guard let match = mapEventToMatch(event) else { return nil }
            let currentSet = (event.match?.games?.filter { $0.state == "completed" }.count ?? 0) + 1
            return LiveMatch(match: match, currentSet: currentSet, lastUpdated: Date())
        }
    }

    // MARK: - Private

    private func mapEventToMatch(_ event: EventDTO, fallbackLeague: League? = nil) -> Match? {
        guard let matchDTO = event.match, matchDTO.teams.count >= 2 else { return nil }
        let league = League(
            id: event.league.id ?? event.league.slug,
            name: event.league.name,
            region: fallbackLeague?.region ?? "",
            imageURL: fallbackLeague?.imageURL
        )
        let teamA = Team(
            id: matchDTO.teams[0].id ?? matchDTO.teams[0].code,
            name: matchDTO.teams[0].name,
            code: matchDTO.teams[0].code,
            imageURL: https(matchDTO.teams[0].image)
        )
        let teamB = Team(
            id: matchDTO.teams[1].id ?? matchDTO.teams[1].code,
            name: matchDTO.teams[1].name,
            code: matchDTO.teams[1].code,
            imageURL: https(matchDTO.teams[1].image)
        )
        let state = MatchState(rawValue: event.state) ?? .unstarted
        return Match(
            id: matchDTO.id,
            league: league,
            teamA: teamA,
            teamB: teamB,
            scoreA: matchDTO.teams[0].result?.gameWins ?? 0,
            scoreB: matchDTO.teams[1].result?.gameWins ?? 0,
            startTime: event.startTime,
            state: state,
            blockName: event.blockName
        )
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(string: baseURL + path)
        var items = [URLQueryItem(name: "hl", value: "ko-KR")]
        items.append(contentsOf: queryItems)
        components?.queryItems = items

        guard let url = components?.url else { throw APIError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return data
    }

    func fetchTournaments(leagueId: String) async throws -> [Tournament] {
        let query = [URLQueryItem(name: "leagueId", value: leagueId)]
        let data = try await request(path: "/getTournamentsForLeague", queryItems: query)
        let response = try decode(TournamentsResponse.self, from: data)
        return response.data.leagues.flatMap { $0.tournaments }.map {
            Tournament(id: $0.id, slug: $0.slug, startDate: $0.startDate, endDate: $0.endDate)
        }
    }

    func fetchStandings(tournamentId: String) async throws -> [Standing] {
        let query = [URLQueryItem(name: "tournamentId", value: tournamentId)]
        let data = try await request(path: "/getStandings", queryItems: query)
        let response = try decode(StandingsResponse.self, from: data)
        // "groups" 타입(정규시즌) 스테이지 우선, 없으면 랭킹이 가장 많은 스테이지
        let standingGroup = response.data.standings.first
        let stage = standingGroup?.stages.first { $0.type == "groups" }
                 ?? standingGroup?.stages.max(by: {
                     $0.sections.flatMap { $0.rankings }.count < $1.sections.flatMap { $0.rankings }.count
                 })
        // 모든 섹션의 랭킹을 합치고, 동률 팀도 모두 포함
        let allRankings = stage?.sections.flatMap { $0.rankings } ?? []
        return allRankings.flatMap { ranking in
            ranking.teams.map { dto in
                let team = Team(id: dto.id, name: dto.name, code: dto.code, imageURL: https(dto.image))
                let total = dto.record.wins + dto.record.losses
                let winRate = total > 0 ? Double(dto.record.wins) / Double(total) : 0
                return Standing(team: team, wins: dto.record.wins, losses: dto.record.losses,
                                rank: ranking.ordinal, winRate: winRate)
            }
        }
        .sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            return $0.team.name < $1.team.name
        }
    }

    func fetchTeamRoster(teamId: String) async throws -> [Player] {
        let query = [URLQueryItem(name: "id", value: teamId)]
        let data = try await request(path: "/getTeams", queryItems: query)
        let response = try decode(TeamsResponse.self, from: data)
        guard let team = response.data.teams.first else { return [] }
        return (team.players ?? []).map { p in
            Player(id: p.id, summonerName: p.summonerName,
                   firstName: p.firstName, lastName: p.lastName,
                   role: p.role ?? "", imageURL: https(p.image),
                   teamId: team.id, teamCode: team.code)
        }
    }

    func fetchEventDetails(matchId: String) async throws -> EventDetailInfo {
        let query = [URLQueryItem(name: "id", value: matchId)]
        let data = try await request(path: "/getEventDetails", queryItems: query)
        let response = try decode(EventDetailsResponse.self, from: data)
        let matchDTO = response.data.event.match

        let games = matchDTO.games.map { game -> GameInfo in
            let blueTeamId = game.teams.first { $0.side == "blue" }?.id ?? ""
            let redTeamId  = game.teams.first { $0.side == "red"  }?.id ?? ""
            let state = GameInfoState(rawValue: game.state) ?? .unstarted
            return GameInfo(number: game.number, gameId: game.id, state: state,
                            blueTeamId: blueTeamId, redTeamId: redTeamId)
        }

        return EventDetailInfo(strategyCount: matchDTO.strategy.count, games: games)
    }

    private func https(_ url: String?) -> String? {
        url?.replacingOccurrences(of: "http://", with: "https://")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}
