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
    var loadFailed = false

    // MARK: - Search

    func results(for query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        // `lazy`가 없으면 filter가 후보 전체(선수만 1300명대)를 한 번 다 훑어 배열로 만든 뒤
        // 거기서 앞 10개만 취한다. lazy를 끼우면 필요한 개수를 채우는 즉시 멈춘다 —
        // 이 함수는 뷰 body에서 호출돼 키 입력마다 다시 도는 자리라 차이가 그대로 체감된다
        // (실측: 쿼리 "a" 기준 0.488ms → 0.005ms).
        var out: [SearchResult] = []
        out += allLeagues.lazy
            .filter { $0.name.lowercased().contains(q) || $0.region.lowercased().contains(q) }
            .prefix(3)
            .map { SearchResult.league($0) }
        out += allTeams.lazy
            .filter { $0.team.name.lowercased().contains(q) || $0.team.code.lowercased().contains(q) }
            .prefix(10)
            .map { SearchResult.team($0.team, league: $0.league) }
        out += allPlayers.lazy
            .filter {
                $0.player.summonerName.lowercased().contains(q) ||
                ($0.player.firstName?.lowercased().contains(q) ?? false) ||
                ($0.player.lastName?.lowercased().contains(q) ?? false)
            }
            .prefix(10)
            .map { SearchResult.player($0.player, league: $0.league) }
        return out
    }

    // MARK: - Load

    private let service: RiotEsportsServiceProtocol

    init(service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.service = service
    }

    func load() async {
        guard allLeagues.isEmpty else { return }
        // 캐시 읽기가 비동기라 로딩 표시를 먼저 켜둔다(빈 상태가 한 프레임 스치는 것 방지).
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        if await preloadFromCache() { return }

        guard let leagues = try? await service.fetchLeagues() else {
            loadFailed = true
            return
        }
        allLeagues = leagues

        let svc = service

        // 리그별 팀+선수 병렬 로드
        let pairs: [(teams: [(Team, League)], players: [(Player, League)])] =
            await withTaskGroup(of: (teams: [(Team, League)], players: [(Player, League)]).self) { group in
                for league in leagues {
                    group.addTask {
                        guard let tournaments = try? await svc.fetchTournaments(leagueId: league.id),
                              let tournament = activeTournament(from: tournaments) else { return ([], []) }

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
        let allTeamPairs:   [(Team, League)]   = pairs.flatMap { $0.teams }
        let allPlayerPairs: [(Player, League)] = pairs.flatMap { $0.players }

        var seenTeams = Set<String>()
        for (team, league) in allTeamPairs.sorted(by: { !isInternational($0.1) && isInternational($1.1) }) {
            if seenTeams.insert(team.id).inserted {
                allTeams.append((team: team, league: league))
            }
        }

        var seenPlayers = Set<String>()
        for (player, league) in allPlayerPairs.sorted(by: {
            let scoreA = isInternational($0.1) ? 2 : (isSecondaryLeague($0.1) ? 1 : 0)
            let scoreB = isInternational($1.1) ? 2 : (isSecondaryLeague($1.1) ? 1 : 0)
            return scoreA < scoreB
        }) {
            if seenPlayers.insert(player.id).inserted {
                allPlayers.append((player: player, league: league))
            }
        }

        let teamEntries = allTeams.map { SearchTeamEntry(team: $0.team, league: $0.league) }
        let playerEntries = allPlayers.map { SearchPlayerEntry(player: $0.player, league: $0.league) }
        AppDiskCache.set(key: "search_teams", value: teamEntries)
        AppDiskCache.set(key: "search_players", value: playerEntries)

        // 선수 목록 완료 후 1군 리그 스탯 백그라운드 프리로드
        let primaryLeagues = leagues.filter { isPrimary($0) }
        Task.detached(priority: .background) {
            for league in primaryLeagues {
                await LeaguepediaService.shared.preloadLeagueStats(for: league)
            }
        }
    }

    /// 검색 탭은 리그·팀·선수 캐시 세 덩어리를 한 번에 읽는다. 메인 액터에서 그대로 돌리면
    /// 탭 전환 애니메이션 도중 메인 스레드가 막히므로 읽기만 백그라운드로 뺀다.
    private nonisolated static func readDiskPreload()
        -> (leagues: [League], teams: [SearchTeamEntry], players: [SearchPlayerEntry])? {
        guard let cachedLeagues: [League] = AppDiskCache.get(.leagues),
              let teams: [SearchTeamEntry] = AppDiskCache.get(key: "search_teams", maxAge: 12 * 3600),
              let players: [SearchPlayerEntry] = AppDiskCache.get(key: "search_players", maxAge: 12 * 3600),
              !cachedLeagues.isEmpty
        else { return nil }
        return (cachedLeagues, teams, players)
    }

    private func preloadFromCache() async -> Bool {
        let preload = await Task.detached(priority: .userInitiated) {
            Self.readDiskPreload()
        }.value
        guard let result = preload else { return false }
        let cachedLeagues = result.leagues
        let teams = result.teams
        let players = result.players
        allLeagues = cachedLeagues
        allTeams = teams.map { (team: $0.team, league: $0.league) }
        allPlayers = players.map { (player: $0.player, league: $0.league) }
        let primaryLeagues = cachedLeagues.filter { isPrimary($0) }
        Task.detached(priority: .background) {
            for league in primaryLeagues {
                await LeaguepediaService.shared.preloadLeagueStats(for: league)
            }
        }
        return true
    }


    private let primaryLeagueIDs: Set<String> = [
        "98767991310872058",  // LCK
        "98767991314006698",  // LPL
        "98767991302996019",  // LEC
        "98767991299243165",  // LCS
        "104366947889790212", // PCS
        "107213827295848783", // VCS
        "98767991332355509",  // CBLOL
        "98767991349978712",  // LJL
        "105709090213554609", // LCO
        "101382741235120470", // LLA
        "113476371197627891", // LCP
    ]

    private func isPrimary(_ league: League) -> Bool {
        if primaryLeagueIDs.contains(league.id) { return true }
        let slug = league.slug.lowercased().trimmingCharacters(in: .whitespaces)
        let name = league.name.lowercased().trimmingCharacters(in: .whitespaces)
        let knownSlugs: Set<String> = ["lck","lpl","lec","lcs","pcs","vcs","lco","lla","lcp"]
        let knownNames: Set<String> = ["lck","lpl","lec","lcs","pcs","vcs","cblol","ljl","lco","lla","lcp"]
        if !slug.isEmpty && knownSlugs.contains(slug) { return true }
        if knownNames.contains(name) { return true }
        if name.contains("챌린저스") || slug.contains("챌린저스")        { return false }
        if name.contains("challengers") || slug.contains("challengers")   { return false }
        if name.contains("academy")     || slug.contains("academy")       { return false }
        if name.contains("development") || slug.contains("development")   { return false }
        if slug.contains("challengers_league")                            { return false }
        if name.hasSuffix(" cl") || name.contains(" cl ")                { return false }
        if name == "ldl" || slug == "ldl"                                { return false }
        return false
    }

    private func isSecondaryLeague(_ league: League) -> Bool {
        !isInternational(league) && !isPrimary(league)
    }

    private struct SearchTeamEntry: Codable {
        let team: Team
        let league: League
    }

    private struct SearchPlayerEntry: Codable {
        let player: Player
        let league: League
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
