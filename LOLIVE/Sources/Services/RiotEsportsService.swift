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
    func fetchAllSchedule(league: League) async throws -> [Match]
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
        if let cached: [League] = AppDiskCache.get(.leagues) { return cached }
        let data = try await request(path: "/getLeagues", queryItems: [])
        let response = try decode(LeaguesResponse.self, from: data)
        let leagues = response.data.leagues.map {
            League(id: $0.id, slug: $0.slug ?? "", name: $0.name, region: $0.region, imageURL: https($0.image))
        }
        AppDiskCache.set(.leagues, value: leagues)
        return leagues
    }

    func fetchSchedule(league: League) async throws -> [Match] {
        let cacheKey = CacheKey.schedule(leagueId: league.id)
        if let cached: [Match] = AppDiskCache.get(cacheKey) { return cached }

        var allMatches: [Match] = []
        var seen = Set<String>()

        // 첫 페이지 (오늘 기준)
        let query = [URLQueryItem(name: "leagueId", value: league.id)]
        let data = try await request(path: "/getSchedule", queryItems: query)
        let response = try decode(ScheduleResponse.self, from: data)
        for m in response.data.schedule.events.compactMap({ mapEventToMatch($0, fallbackLeague: league) }) {
            if seen.insert(m.id).inserted { allMatches.append(m) }
        }

        // 미래 경기 페이지 (newer) 최대 3페이지 추가
        var newerToken = response.data.schedule.pages?.newer
        var newerCount = 0
        while let token = newerToken, newerCount < 3 {
            var q = [URLQueryItem(name: "leagueId", value: league.id),
                     URLQueryItem(name: "pageToken", value: token)]
            if let d = try? await request(path: "/getSchedule", queryItems: q),
               let r = try? decode(ScheduleResponse.self, from: d) {
                for m in r.data.schedule.events.compactMap({ mapEventToMatch($0, fallbackLeague: league) }) {
                    if seen.insert(m.id).inserted { allMatches.append(m) }
                }
                newerToken = r.data.schedule.pages?.newer
            } else {
                break
            }
            newerCount += 1
        }

        // 과거 완료 경기 페이지 (older) 최대 2페이지 추가
        // "오늘 기준" 첫 페이지만으로는 며칠 전 완료 경기가 누락될 수 있음 (TodayView 날짜 스트립 -5일 대응)
        var olderToken = response.data.schedule.pages?.older
        var olderCount = 0
        while let token = olderToken, olderCount < 2 {
            var q = [URLQueryItem(name: "leagueId", value: league.id),
                     URLQueryItem(name: "pageToken", value: token)]
            if let d = try? await request(path: "/getSchedule", queryItems: q),
               let r = try? decode(ScheduleResponse.self, from: d) {
                for m in r.data.schedule.events.compactMap({ mapEventToMatch($0, fallbackLeague: league) }) {
                    if seen.insert(m.id).inserted { allMatches.append(m) }
                }
                olderToken = r.data.schedule.pages?.older
            } else {
                break
            }
            olderCount += 1
        }

        allMatches = await reconcileUnreportedResults(allMatches, league: league)

        AppDiskCache.set(cacheKey, value: allMatches)
        return allMatches
    }

    /// 케스파컵처럼 Riot이 경기 상태/결과를 갱신해주지 않는 대회 대응.
    /// 시작 시각이 한참 지났는데도 unstarted로 멈춰있거나, completed인데 스코어(gameWins)가
    /// 비어 있어 0:0으로 내려오는 경기가 있으면 Leaguepedia 결과로 보완한다.
    /// (LoL 경기는 정상 종료 시 0:0으로 끝날 수 없으므로 이 조건으로 걸러도 안전하다)
    /// 정상적으로 상태가 갱신되는 리그(대부분)는 감지되는 게 없어 API 호출 없이 그대로 반환된다.
    private func reconcileUnreportedResults(_ matches: [Match], league: League) async -> [Match] {
        let cutoff = Date().addingTimeInterval(-3 * 3600)
        let hasStale = matches.contains {
            ($0.state == .unstarted && $0.startTime < cutoff) ||
            ($0.state == .completed && $0.scoreA == 0 && $0.scoreB == 0)
        }
        guard hasStale else { return matches }

        let lpMatches = await LeaguepediaService.shared.fetchLiveTournamentResults(for: league)
        guard !lpMatches.isEmpty else { return matches }
        return LeaguepediaService.shared.reconcileResults(riotMatches: matches, leaguepediaMatches: lpMatches)
    }

    // 국제 대회(Worlds/MSI) 전용: 모든 페이지를 순회하여 전체 경기 목록 반환
    func fetchAllSchedule(league: League) async throws -> [Match] {
        let cacheKey = CacheKey.allSchedule(leagueId: league.id)
        if let cached: [Match] = AppDiskCache.get(cacheKey) { return cached }
        var allMatches: [Match] = []
        var pageToken: String? = nil
        var pageCount = 0
        let maxPages = 60

        repeat {
            var query = [URLQueryItem(name: "leagueId", value: league.id)]
            if let token = pageToken {
                query.append(URLQueryItem(name: "pageToken", value: token))
            }

            do {
                let data = try await request(path: "/getSchedule", queryItems: query)
                let response = try decode(ScheduleResponse.self, from: data)
                let page = response.data.schedule.events
                    .compactMap { mapEventToMatch($0, fallbackLeague: league) }
                allMatches.append(contentsOf: page)
                pageToken = response.data.schedule.pages?.older
            } catch {
                // 특정 페이지 오류는 건너뛰고 수집된 데이터 반환
                break
            }

            pageCount += 1
        } while pageToken != nil && pageCount < maxPages

        // 중복 제거 (match ID 기준)
        var seen = Set<String>()
        var result = allMatches.filter { seen.insert($0.id).inserted }
        result = await reconcileUnreportedResults(result, league: league)
        if !result.isEmpty { AppDiskCache.set(cacheKey, value: result) }
        return result
    }

    func fetchLive() async throws -> [LiveMatch] {
        do {
            let data = try await request(path: "/getLive", queryItems: [])
            let response = try decode(LiveResponse.self, from: data)
            let live = response.data.schedule.events.compactMap { event -> LiveMatch? in
                guard let match = mapEventToMatch(event) else { return nil }
                let currentSet = (event.match?.games?.filter { $0.state == "completed" }.count ?? 0) + 1
                let currentGameId = event.match?.games?.first { $0.state == "inProgress" }?.id
                return LiveMatch(match: match, currentSet: currentSet, lastUpdated: Date(), currentGameId: currentGameId)
            }
            AppDiskCache.set(.live, value: live)
            return live
        } catch {
            // 네트워크 순간 장애 대응: 5분 이내 캐시가 있으면 폴백, 없으면(오래 끊겼으면) 에러 그대로 전달
            // (30초 폴링 주기 특성상 5분이면 이미 여러 번 재시도할 시간이라 낡은 데이터를 오래 우려먹진 않음)
            if let cached: [LiveMatch] = AppDiskCache.get(.live) {
                return cached
            }
            throw error
        }
    }

    // MARK: - Private

    private func mapEventToMatch(_ event: EventDTO, fallbackLeague: League? = nil) -> Match? {
        guard let matchDTO = event.match, matchDTO.teams.count >= 2 else { return nil }
        let league = League(
            id: fallbackLeague?.id ?? event.league.id ?? event.league.slug,
            slug: event.league.slug,
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
            if $0.group != $1.group { return ($0.group ?? "") < ($1.group ?? "") }
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
