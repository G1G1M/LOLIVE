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
    }

    struct MatchResult: Identifiable {
        let id: String
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
    private let liveStatsService: LiveStatsServiceProtocol

    // MARK: - Init

    init(player: Player, league: League,
         service: RiotEsportsServiceProtocol = RiotEsportsService(),
         liveStatsService: LiveStatsServiceProtocol = LiveStatsService()) {
        self.player = player
        self.league = league
        self.service = service
        self.liveStatsService = liveStatsService
    }

    // MARK: - Public

    func load() async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        let allMatches = (try? await service.fetchSchedule(league: league)) ?? []

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
            return MatchResult(id: match.id, opponent: opponent, won: my > opp,
                               myScore: my, oppScore: opp, date: match.startTime)
        }

        // 챔피언 데이터: 각 경기의 게임 윈도우 메타데이터에서 추출
        let svc = service
        let lsvc = liveStatsService
        let summonerName = player.summonerName

        var championCounts: [String: Int] = [:]

        await withTaskGroup(of: [String].self) { group in
            for match in teamMatches {
                group.addTask {
                    guard let detail = try? await svc.fetchEventDetails(matchId: match.id) else { return [] }
                    var picks: [String] = []
                    for game in detail.games where game.state.isPlayable {
                        // gameMetadata는 startingTime 없이도 항상 반환됨 (챔피언 ID 포함)
                        guard let window = try? await lsvc.fetchGameWindow(gameId: game.gameId, startingTime: nil)
                        else { continue }
                        let allPlayers = window.bluePlayers + window.redPlayers
                        if let found = allPlayers.first(where: { $0.summonerName == summonerName }),
                           !found.championId.isEmpty {
                            picks.append(found.championId)
                        }
                    }
                    return picks
                }
            }
            for await picks in group {
                for champ in picks {
                    championCounts[champ, default: 0] += 1
                }
            }
        }

        championStats = championCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ChampionStat(championId: $0.key, games: $0.value) }
    }
}
