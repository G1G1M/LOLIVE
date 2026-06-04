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
        var entries: [ChampionPickEntry] = []
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
    var seasonStats: PlayerSeasonStats? = nil
    var isLoadingStats = true

    // MARK: - Private

    private let player: Player
    private let league: League
    private let service: RiotEsportsServiceProtocol
    private var hasStartedLoad = false

    // MARK: - Init

    init(player: Player, league: League,
         service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.player = player
        self.league = league
        self.service = service
    }

    // MARK: - Public

    func load() async {
        guard !hasStartedLoad else { return }
        hasStartedLoad = true

        // 세 요청 동시 시작
        async let scheduleTask = service.fetchSchedule(league: league)
        async let seasonStatsTask = LeaguepediaService.shared.playerSeasonStats(
            summonerName: player.summonerName, league: league
        )
        async let picksTask = LeaguepediaService.shared.playerChampionPicks(
            summonerName: player.summonerName, league: league
        )

        // 스케줄은 빠른 Riot API → 완료 즉시 최근 경기 표시 (Leaguepedia 대기 없음)
        let allMatches = (try? await scheduleTask) ?? []
        let teamMatches = allMatches
            .filter {
                ($0.teamA.id == player.teamId || $0.teamA.code == player.teamCode ||
                 $0.teamB.id == player.teamId || $0.teamB.code == player.teamCode) &&
                $0.state == .completed
            }
            .sorted { $0.startTime > $1.startTime }
            .prefix(5)
            .map { $0 }
        recentResults = teamMatches.map { match in
            let isTeamA = match.teamA.id == player.teamId || match.teamA.code == player.teamCode
            let opponent = isTeamA ? match.teamB : match.teamA
            let my  = isTeamA ? match.scoreA : match.scoreB
            let opp = isTeamA ? match.scoreB : match.scoreA
            return MatchResult(id: match.id, match: match, opponent: opponent, won: my > opp,
                               myScore: my, oppScore: opp, date: match.startTime)
        }

        // Leaguepedia는 이미 병렬 실행 중 — 완료되면 순서대로 반영
        defer { isLoadingStats = false }

        seasonStats = await seasonStatsTask

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

            var champEntries: [String: [ChampionPickEntry]] = [:]
            for pick in picks { champEntries[pick.champion, default: []].append(pick) }

            championStats = champGames.keys
                .sorted { (champGames[$0] ?? 0) > (champGames[$1] ?? 0) }
                .map {
                    ChampionStat(
                        championId: $0,
                        games:      champGames[$0]   ?? 0,
                        wins:       champWins[$0]    ?? 0,
                        kills:      champKills[$0]   ?? 0,
                        deaths:     champDeaths[$0]  ?? 0,
                        assists:    champAssists[$0] ?? 0,
                        entries:    (champEntries[$0] ?? []).sorted {
                            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
                        }
                    )
                }
        }
    }
}
