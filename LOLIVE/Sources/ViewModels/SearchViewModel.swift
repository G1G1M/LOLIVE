//
//  SearchViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {

    // MARK: - Result Types

    enum SearchResult: Identifiable {
        case league(League)
        case team(Team, league: League)
        case player(Player, league: League)

        var id: String {
            switch self {
            case .league(let l):  return "league_\(l.id)"
            case .team(let t, _): return "team_\(t.id)"
            case .player(let p, _): return "player_\(p.id)"
            }
        }
    }

    // MARK: - Properties

    var allLeagues: [League] = []
    var allTeams:   [(team: Team, league: League)] = []
    var allPlayers: [(player: Player, league: League)] = []
    var isLoading = false

    // MARK: - Search

    func results(for query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        var out: [SearchResult] = []
        out += allLeagues
            .filter { $0.name.lowercased().contains(q) || $0.region.lowercased().contains(q) }
            .prefix(3)
            .map { .league($0) }
        out += allTeams
            .filter { $0.team.name.lowercased().contains(q) || $0.team.code.lowercased().contains(q) }
            .prefix(10)
            .map { .team($0.team, league: $0.league) }
        out += allPlayers
            .filter {
                $0.player.summonerName.lowercased().contains(q) ||
                ($0.player.firstName?.lowercased().contains(q) ?? false) ||
                ($0.player.lastName?.lowercased().contains(q) ?? false)
            }
            .prefix(10)
            .map { .player($0.player, league: $0.league) }
        return out
    }

    // MARK: - Load

    private let service: RiotEsportsServiceProtocol

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
    }

    func load() async {
        guard allLeagues.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let leagues = (try? await service.fetchLeagues()) ?? []
        allLeagues = leagues

        let svc = service

        // 리그별 팀+선수 병렬 로드
        let pairs: [(teams: [(Team, League)], players: [(Player, League)])] =
            await withTaskGroup(of: (teams: [(Team, League)], players: [(Player, League)]).self) { group in
                for league in leagues {
                    group.addTask {
                        guard let tournaments = try? await svc.fetchTournaments(leagueId: league.id),
                              let tournament = self.activeTournament(from: tournaments) else { return ([], []) }

                        let standings = (try? await svc.fetchStandings(tournamentId: tournament.id)) ?? []
                        let teams: [(Team, League)] = standings.map { ($0.team, league) }

                        let players: [(Player, League)] = await withTaskGroup(of: [Player].self) { rg in
                            for s in standings {
                                rg.addTask { (try? await svc.fetchTeamRoster(teamId: s.team.id)) ?? [] }
                            }
                            var all: [Player] = []
                            for await roster in rg { all.append(contentsOf: roster) }
                            return all
                        }.map { ($0, league) }

                        return (teams, players)
                    }
                }
                var result: [(teams: [(Team, League)], players: [(Player, League)])] = []
                for await pair in group { result.append(pair) }
                return result
            }

        // 국제 대회(MSI, Worlds 등)보다 지역 리그 우선 정렬 후 중복 제거
        var allTeamPairs:   [(Team, League)]   = pairs.flatMap { $0.teams }
        var allPlayerPairs: [(Player, League)] = pairs.flatMap { $0.players }

        var seenTeams = Set<String>()
        for (team, league) in allTeamPairs.sorted(by: { !isInternational($0.1) && isInternational($1.1) }) {
            if seenTeams.insert(team.id).inserted {
                allTeams.append((team: team, league: league))
            }
        }

        var seenPlayers = Set<String>()
        for (player, league) in allPlayerPairs.sorted(by: { !isInternational($0.1) && isInternational($1.1) }) {
            if seenPlayers.insert(player.id).inserted {
                allPlayers.append((player: player, league: league))
            }
        }
    }

    private nonisolated func activeTournament(from tournaments: [Tournament]) -> Tournament? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let active = tournaments.first {
            guard let s = fmt.date(from: $0.startDate),
                  let e = fmt.date(from: $0.endDate) else { return false }
            return now >= s && now <= e
        }
        return active ?? tournaments.last
    }

    private func isInternational(_ league: League) -> Bool {
        let name   = league.name.lowercased()
        let region = league.region.lowercased()
        return name.contains("msi") ||
               name.contains("worlds") ||
               name.contains("mid-season") ||
               name.contains("world championship") ||
               name.contains("all-star") ||
               region.contains("international") ||
               region.contains("국제")
    }
}
