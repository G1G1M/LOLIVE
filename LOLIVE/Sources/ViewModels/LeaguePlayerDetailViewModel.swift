//
//  LeaguePlayerDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class LeaguePlayerDetailViewModel {

    // MARK: - Types

    struct ChampionStat: Identifiable {
        var id: String { championId }
        let championId: String
        var games: Int
        var wins: Int = 0
        var kills: Int = 0
        var deaths: Int = 0
        var assists: Int = 0
        var kda: Double {
            deaths == 0 ? Double(kills + assists) : Double(kills + assists) / Double(deaths)
        }
        var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
    }

    struct MatchResult: Identifiable {
        let id: String
        let match: Match
        let opponent: Team
        let won: Bool
        let myScore: Int
        let oppScore: Int
        let date: Date
    }

    // MARK: - Properties

    var recentResults: [MatchResult] = []
    var championStats: [ChampionStat] = []
    var isLoadingStats = false

    // MARK: - Private

    private let player: Player
    private let league: League
    private let service: RiotEsportsServiceProtocol

    // MARK: - Init

    init(player: Player, league: League,
         service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.player = player
        self.league = league
        self.service = service
    }

    // MARK: - Public

    func load() async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        async let scheduleTask = service.fetchSchedule(league: league)
        async let picksTask = LeaguepediaService.shared.playerChampionPicks(
            summonerName: player.summonerName, league: league
        )

        let allMatches = (try? await scheduleTask) ?? []

        // 선수가 속한 팀의 완료된 경기 (최근 5경기)
        let teamMatches = allMatches
            .filter {
                ($0.teamA.id == player.teamId || $0.teamA.code == player.teamCode ||
                 $0.teamB.id == player.teamId || $0.teamB.code == player.teamCode) &&
                $0.state == .completed
            }
            .sorted { $0.startTime > $1.startTime }
            .prefix(5)
            .map { $0 }

        // 최근 경기 결과 생성
        recentResults = teamMatches.map { match in
            let isTeamA = match.teamA.id == player.teamId || match.teamA.code == player.teamCode
            let opponent = isTeamA ? match.teamB : match.teamA
            let my  = isTeamA ? match.scoreA : match.scoreB
            let opp = isTeamA ? match.scoreB : match.scoreA
            return MatchResult(id: match.id, match: match, opponent: opponent, won: my > opp,
                               myScore: my, oppScore: opp, date: match.startTime)
        }

        let picks = await picksTask
        if let picks = picks, !picks.isEmpty {
            var champGames:   [String: Int] = [:]
            var champWins:    [String: Int] = [:]
            var champKills:   [String: Int] = [:]
            var champDeaths:  [String: Int] = [:]
            var champAssists: [String: Int] = [:]

            for pick in picks {
                champGames[pick.champion, default: 0]   += 1
                champKills[pick.champion, default: 0]   += pick.kills
                champDeaths[pick.champion, default: 0]  += pick.deaths
                champAssists[pick.champion, default: 0] += pick.assists
                if pick.won { champWins[pick.champion, default: 0] += 1 }
            }

            championStats = champGames.keys
                .sorted { (champGames[$0] ?? 0) > (champGames[$1] ?? 0) }
                .map {
                    ChampionStat(
                        championId: $0,
                        games:   champGames[$0]   ?? 0,
                        wins:    champWins[$0]    ?? 0,
                        kills:   champKills[$0]   ?? 0,
                        deaths:  champDeaths[$0]  ?? 0,
                        assists: champAssists[$0] ?? 0
                    )
                }
        }
    }
}
