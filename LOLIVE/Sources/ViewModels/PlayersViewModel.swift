//
//  PlayersViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class PlayersViewModel {

    // MARK: - Types

    struct PlayerEntry: Identifiable {
        var id: String { "\(league.id)_\(player.id)" }
        let player: Player
        let league: League
        let teamImageURL: String?
    }

    // MARK: - Properties

    var allPlayers: [PlayerEntry] = []
    var leagues: [League] = []
    var isLoading = false
    var selectedRole: String? = nil
    var selectedLeagueId: String? = nil
    var searchText = ""

    // MARK: - Private

    private let service: RiotEsportsServiceProtocol

    // 국제 대회(Worlds, MSI 등)는 소속 리그가 아니므로 제외
    private let excludedRegions: Set<String> = ["국제 대회"]

    // MARK: - Init

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
    }

    // MARK: - Filtered

    var filteredPlayers: [PlayerEntry] {
        allPlayers
            .filter { selectedLeagueId == nil || $0.league.id == selectedLeagueId }
            .filter {
                guard let selected = selectedRole else { return true }
                let r = $0.player.role.lowercased()
                return selected == "bottom" ? (r == "bottom" || r == "bot") : r == selected
            }
            .filter {
                guard !searchText.isEmpty else { return true }
                return $0.player.summonerName.localizedCaseInsensitiveContains(searchText) ||
                       ($0.player.firstName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                       ($0.player.lastName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let svc = service

        // 1. 전체 리그 로드 → 국제 대회 제외
        let fetchedLeagues = (try? await svc.fetchLeagues()) ?? []
        let loadableLeagues = fetchedLeagues.filter { !excludedRegions.contains($0.region) }

        // 필터 칩: 1군 + 2군(챌린저스) 모두 표시하되 지역 순서로 정렬
        leagues = loadableLeagues
            .sorted { regionOrder($0.region) < regionOrder($1.region) }

        // 2. 모든 리그(1군+2군) 병렬 로드
        let leaguepedia = LeaguepediaService.shared
        var entries: [PlayerEntry] = []
        await withTaskGroup(of: [PlayerEntry].self) { group in
            for league in loadableLeagues {
                group.addTask {
                    guard let tournaments = try? await svc.fetchTournaments(leagueId: league.id),
                          let tournament = pickActiveTournament(from: tournaments) else { return [] }

                    let standings = (try? await svc.fetchStandings(tournamentId: tournament.id)) ?? []
                    guard !standings.isEmpty else { return [] }

                    // Leaguepedia에서 이 리그의 공식 선수 목록 조회 (Riot API와 병렬 진행)
                    let validNames = await leaguepedia.playerNames(league: league)

                    return await withTaskGroup(of: [PlayerEntry].self) { rosterGroup in
                        for standing in standings {
                            rosterGroup.addTask {
                                let players = (try? await svc.fetchTeamRoster(teamId: standing.team.id)) ?? []
                                let filtered: [Player]
                                if let validNames {
                                    // Leaguepedia 공식 명단에 있는 선수만 포함
                                    filtered = players.filter {
                                        validNames.contains($0.summonerName.lowercased())
                                    }
                                } else {
                                    // Fallback: 포지션별 1명 (Riot API 조직 전체 반환 대응)
                                    var seenRole = Set<String>()
                                    filtered = players.filter { p in
                                        let role = p.role.lowercased()
                                        guard !role.isEmpty else { return false }
                                        return seenRole.insert(role).inserted
                                    }
                                }
                                return filtered.map {
                                    PlayersViewModel.PlayerEntry(
                                        player: $0,
                                        league: league,
                                        teamImageURL: standing.team.imageURL
                                    )
                                }
                            }
                        }
                        var result: [PlayerEntry] = []
                        for await roster in rosterGroup { result.append(contentsOf: roster) }
                        return result
                    }
                }
            }
            for await leagueEntries in group {
                entries.append(contentsOf: leagueEntries)
            }
        }

        // 3. 1군/2군 분리 후 중복 제거
        // - 1군 선수를 먼저 확정
        // - 2군에서는 1군에 없는 선수만 추가 (Riot API가 조직 전체 명단을 반환하므로 대부분 중복)
        let tier1Entries = entries.filter { !isSecondaryLeague($0.league) }
        let tier2Entries = entries.filter {  isSecondaryLeague($0.league) }

        var seenPlayerIds = Set<String>()
        var deduped: [PlayerEntry] = []

        for entry in tier1Entries where seenPlayerIds.insert(entry.player.id).inserted {
            deduped.append(entry)
        }
        for entry in tier2Entries where seenPlayerIds.insert(entry.player.id).inserted {
            deduped.append(entry)
        }

        allPlayers = deduped.sorted {
            $0.player.summonerName.lowercased() < $1.player.summonerName.lowercased()
        }
    }

    // MARK: - Helpers

    // 2군/챌린저스/아카데미 리그 판별
    // Riot API는 조직 전체 선수를 반환하므로 1군과 중복 → 필터 칩에서 제외, 1군 우선 분류
    private func isSecondaryLeague(_ league: League) -> Bool {
        let name = league.name.lowercased()
        return name.contains("챌린저스") ||
               name.contains("challengers") ||
               name.contains("academy") ||
               name == "circuito desafiante"
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

// MARK: - File-level helper (task group 내부에서 self 없이 호출 가능)

private func pickActiveTournament(from tournaments: [Tournament]) -> Tournament? {
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
