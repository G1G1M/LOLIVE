//
//  StandingsViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class StandingsViewModel {

    // MARK: - Properties

    var leagues: [League] = []
    var standings: [Standing] = []
    var selectedLeague: League? = nil
    var isLoadingLeagues = false
    var isLoadingStandings = false

    // MARK: - Private

    private let service: RiotEsportsServiceProtocol
    private var standingsCache: [String: [Standing]] = [:]

    private let excludedRegions: Set<String> = ["국제 대회"]
    private let secondaryKeywords = ["챌린저스", "challengers", "academy", "circuito desafiante"]

    // MARK: - Init

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
    }

    // MARK: - Public

    func loadLeagues() async {
        isLoadingLeagues = true
        defer { isLoadingLeagues = false }

        let fetched = (try? await service.fetchLeagues()) ?? []
        leagues = fetched
            .filter { !excludedRegions.contains($0.region) }
            .filter { league in
                let name = league.name.lowercased()
                return !secondaryKeywords.contains(where: { name.contains($0) })
            }
            .sorted { regionOrder($0.region) < regionOrder($1.region) }

        // 기본 선택: 첫 번째 리그
        if let first = leagues.first {
            selectedLeague = first
            await loadStandings(for: first)
        }
    }

    func selectLeague(_ league: League) async {
        guard selectedLeague?.id != league.id else { return }
        selectedLeague = league
        await loadStandings(for: league)
    }

    // MARK: - Private

    private func loadStandings(for league: League) async {
        // 캐시 확인
        if let cached = standingsCache[league.id] {
            standings = cached
            return
        }

        isLoadingStandings = true
        defer { isLoadingStandings = false }

        guard let tournaments = try? await service.fetchTournaments(leagueId: league.id),
              let tournament = activeTournament(from: tournaments) else {
            standings = []
            return
        }

        let fetched = (try? await service.fetchStandings(tournamentId: tournament.id)) ?? []
        standingsCache[league.id] = fetched
        standings = fetched
    }

    private func activeTournament(from tournaments: [Tournament]) -> Tournament? {
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

    private func regionOrder(_ region: String) -> Int {
        switch region {
        case "한국":                     return 0
        case "중국":                     return 1
        case "EMEA":                     return 2
        case "북미":                     return 3
        case "퍼시픽":                   return 4
        case "아메리카스":               return 5
        case "일본":                     return 6
        case "베트남":                   return 7
        case "브라질":                   return 8
        case "홍콩, 마카오, 대만":       return 9
        case "라틴 아메리카":            return 10
        case "라틴 아메리카 북부":       return 11
        case "라틴 아메리카 남부":       return 12
        case "오세아니아":               return 13
        case "독립 국가 연합 (CIS)":     return 14
        default:                         return 15
        }
    }
}
