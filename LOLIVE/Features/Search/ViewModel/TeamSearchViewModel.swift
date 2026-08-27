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


    // MSI/Worlds 같은 국제 대회뿐 아니라 케스파컵처럼 지역이 "한국"으로 찍히는
    // 국내 컵 대회도 팀의 정규 소속 리그가 아니므로 포함 — 안 그러면 검색 인덱싱 시
    // 도메인 리그(LCK 등)와 우선순위 다툼에서 이겨서 팀의 소속 리그가 잘못 표시될 수 있다.
    private func isInternational(_ league: League) -> Bool {
        let name   = league.name.lowercased()
        let slug   = league.slug.lowercased()
        let region = league.region.lowercased()
        return name.contains("msi") ||
               name.contains("worlds") ||
               name.contains("mid-season") ||
               name.contains("world championship") ||
               name.contains("all-star") ||
               region.contains("international") ||
               region.contains("국제") ||
               name.contains("kespa") ||
               slug.contains("kespa")
    }
}
