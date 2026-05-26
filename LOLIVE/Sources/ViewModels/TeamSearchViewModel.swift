//
//  TeamSearchViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class TeamSearchViewModel {

    struct TeamResult: Identifiable {
        var id: String { team.id }
        let team: Team
        let league: League
    }

    var allTeams: [TeamResult] = []
    var isLoading = false
    var loadFailed = false

    private let service: RiotEsportsServiceProtocol

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
    }

    func load() async {
        guard allTeams.isEmpty else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        guard let leagues = try? await service.fetchLeagues(), !leagues.isEmpty else {
            loadFailed = true
            return
        }
        let svc = service

        var results: [TeamResult] = []
        await withTaskGroup(of: [TeamResult].self) { group in
            for league in leagues {
                group.addTask {
                    guard let tournaments = try? await svc.fetchTournaments(leagueId: league.id),
                          let tournament = activeTournament(from: tournaments)
                    else { return [] }
                    let standings = (try? await svc.fetchStandings(tournamentId: tournament.id)) ?? []
                    return standings.map { TeamResult(team: $0.team, league: league) }
                }
            }
            for await batch in group { results.append(contentsOf: batch) }
        }

        // 국제 대회(MSI, Worlds 등)보다 지역 리그 우선 정렬 후 중복 제거
        // → 병렬 fetch 완료 순서에 관계없이 항상 홈 리그로 저장됨
        var seen = Set<String>()
        allTeams = results
            .sorted { !isInternational($0.league) && isInternational($1.league) }
            .filter { seen.insert($0.team.id).inserted }
            .sorted { $0.team.name < $1.team.name }
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
