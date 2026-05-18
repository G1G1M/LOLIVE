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

        // 필터 칩: 1군 리그만 지역 순서로 표시
        leagues = loadableLeagues
            .filter { isPrimary($0) }
            .sorted { regionOrder($0.region) < regionOrder($1.region) }

        // 2. 1군+2군 모두 병렬 로드
        //    slug 매칭 실패로 1군이 빠지는 경우에도 선수 누락을 방지하기 위해
        //    모든 리그에서 로스터를 불러온 뒤 3단계에서 1군 우선 dedup 처리
        var entries: [PlayerEntry] = []
        await withTaskGroup(of: [PlayerEntry].self) { group in
            for league in loadableLeagues {
                group.addTask {
                    guard let tournaments = try? await svc.fetchTournaments(leagueId: league.id),
                          let tournament = pickActiveTournament(from: tournaments) else { return [] }

                    let standings = (try? await svc.fetchStandings(tournamentId: tournament.id)) ?? []
                    guard !standings.isEmpty else { return [] }

                    return await withTaskGroup(of: [PlayerEntry].self) { rosterGroup in
                        for standing in standings {
                            rosterGroup.addTask {
                                let players = (try? await svc.fetchTeamRoster(teamId: standing.team.id)) ?? []
                                return players.filter { !$0.role.isEmpty }.map {
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

        // 3. 1군 우선 중복 제거
        //    동일 선수(player.id)가 1군(LCK)과 2군(LCK CL) 양쪽에 있으면
        //    1군 항목을 먼저 추가하고 2군 항목은 건너뜀 → T1A 대신 T1으로 표시
        let primaryEntries   = entries.filter {  isPrimary($0.league) }
        let secondaryEntries = entries.filter { !isPrimary($0.league) }

        var seenPlayerIds = Set<String>()
        var deduped: [PlayerEntry] = []

        for entry in primaryEntries where seenPlayerIds.insert(entry.player.id).inserted {
            deduped.append(entry)
        }
        for entry in secondaryEntries where seenPlayerIds.insert(entry.player.id).inserted {
            deduped.append(entry)
        }

        allPlayers = deduped.sorted {
            $0.player.summonerName.lowercased() < $1.player.summonerName.lowercased()
        }

        // 선수 목록 로드 완료 후 1군 리그 스탯을 백그라운드에서 순서대로 프리로드.
        // 디스크 캐시가 유효하면 즉시 반환되므로 24시간 이내 재실행 시 API 호출 없음.
        let primaryLeagues = leagues
        Task.detached(priority: .background) {
            for league in primaryLeagues {
                await LeaguepediaService.shared.preloadLeagueStats(for: league)
            }
        }
    }

    // MARK: - Primary League Classification

    // 1군 리그 ID (Riot API 고정값 — 리그 이름·slug가 바뀌어도 ID는 불변)
    // API 실측값 기준 (2026-05 확인)
    private let primaryLeagueIDs: Set<String> = [
        "98767991310872058",  // LCK
        "98767991314006698",  // LPL
        "98767991302996019",  // LEC
        "98767991299243165",  // LCS
        "104366947889790212", // PCS  (홍콩·마카오·대만)
        "107213827295848783", // VCS  (베트남)
        "98767991332355509",  // CBLOL (브라질)  slug: cblol-brazil
        "98767991349978712",  // LJL  (일본)     slug: ljl-japan
        "105709090213554609", // LCO  (오세아니아)
        "101382741235120470", // LLA  (라틴아메리카)
        "113476371197627891", // LCP  (퍼시픽 신규 — 2025 이후)
    ]

    /// 리그가 1군인지 판별
    /// 1순위: ID 매칭 (가장 신뢰할 수 있는 기준, Riot이 절대 바꾸지 않음)
    /// 2순위: slug/name 매칭 (ID 목록에 없는 신규 리그 대비 fallback)
    private func isPrimary(_ league: League) -> Bool {
        // 1. ID 직접 매칭 — 가장 확실
        if primaryLeagueIDs.contains(league.id) { return true }

        // 2. slug / name fallback (ID 목록이 갱신되지 않은 신규 리그 대비)
        let slug = league.slug.lowercased().trimmingCharacters(in: .whitespaces)
        let name = league.name.lowercased().trimmingCharacters(in: .whitespaces)

        let knownSlugs: Set<String> = ["lck","lpl","lec","lcs","pcs","vcs","lco","lla","lcp"]
        let knownNames: Set<String> = ["lck","lpl","lec","lcs","pcs","vcs","cblol","ljl","lco","lla","lcp"]

        if !slug.isEmpty && knownSlugs.contains(slug) { return true }
        if knownNames.contains(name) { return true }

        // 3. 2군 패턴이면 false
        if name.contains("챌린저스") || slug.contains("챌린저스")   { return false }
        if name.contains("challengers") || slug.contains("challengers") { return false }
        if name.contains("academy")     || slug.contains("academy")     { return false }
        if name.contains("development") || slug.contains("development") { return false }
        if slug.contains("challengers_league")                          { return false }
        if name.hasSuffix(" cl") || name.contains(" cl ")              { return false }
        if name == "ldl" || slug == "ldl"                              { return false }

        // 4. 판단 불가 → 2군 처리 (알 수 없는 리그가 1군 선수 자리 빼앗지 않도록)
        return false
    }

    // MARK: - Helpers

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
