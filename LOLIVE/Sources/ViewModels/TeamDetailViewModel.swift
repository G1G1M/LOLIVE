//
//  TeamDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

struct H2HRecord: Identifiable {
    var id: String { opponent.id.isEmpty ? opponent.code : opponent.id }
    let opponent: Team
    var wins: Int
    var losses: Int
    var winRate: Double { wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses) }
}

@MainActor
@Observable
final class TeamDetailViewModel {

    var players: [Player] = []
    var recentMatches: [Match] = []
    var h2hRecords: [H2HRecord] = []
    var isLoading = true
    var loadFailed = false

    private let team: Team
    private var league: League
    private let service: RiotEsportsServiceProtocol
    private var crossLeagueMatches: [Match] = []

    init(team: Team, league: League,
         service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.team = team
        self.league = league
        self.service = service
    }

    /// 국제 대회(MSI/Worlds) 컨텍스트에서 홈 리그로 교체 — load() 호출 전에 사용
    func updateLeague(_ newLeague: League) {
        league = newLeague
    }

    /// 다른 리그/대회에서 이미 로드되어 있는 경기 목록을 주입 (예: TodayViewModel).
    /// "최근 경기" 탭이 현재 리그 하나로 fetch가 제한되지 않고, 이 팀이 뛴 다른 대회 경기도 함께 보여줄 수 있도록 함.
    /// load() 호출 전에 사용해야 반영됨.
    func setCrossLeagueMatches(_ matches: [Match]) {
        crossLeagueMatches = matches
    }

    func load() async {
        let hadCache = preloadFromCache()
        isLoading = !hadCache
        loadFailed = false
        defer { isLoading = false }

        async let rosterTask = service.fetchTeamRoster(teamId: team.id)
        // 15분짜리 오늘 기준 스케줄이 아니라, 과거 페이지까지 전부 훑는 전체 시즌 스케줄을 사용해야
        // 최근 맞대결이 없어도 상대 전적·최근 경기가 안정적으로 채워짐
        async let scheduleTask = service.fetchAllSchedule(league: league)

        let rosterResult = try? await rosterTask
        let matchResult  = try? await scheduleTask

        if !hadCache && rosterResult == nil && matchResult == nil {
            loadFailed = true
            return
        }

        let roster = rosterResult ?? []
        players = roster.sorted { roleOrder($0.role) < roleOrder($1.role) }
        applyMatches(matchResult ?? [])
    }

    private func preloadFromCache() -> Bool {
        var hadAny = false
        if let roster: [Player] = AppDiskCache.get(key: "roster_\(team.id)", maxAge: 12 * 3600) {
            players = roster.sorted { roleOrder($0.role) < roleOrder($1.role) }
            hadAny = true
        }
        if let allMatches: [Match] = AppDiskCache.get(key: "all_schedule_\(league.id)", maxAge: 2 * 3600) {
            applyMatches(allMatches)
            hadAny = true
        }
        return hadAny
    }

    /// 현재 리그 전체 스케줄 + 교차 리그(국제 대회 등) 경기를 합쳐
    /// "최근 경기"는 대회 상관없이 전부, "상대 전적"은 현재 리그/대회 내 경기만으로 구성한다.
    private func applyMatches(_ leagueMatches: [Match]) {
        func isThisTeam(_ m: Match) -> Bool {
            m.teamA.id == team.id || m.teamA.code == team.code ||
            m.teamB.id == team.id || m.teamB.code == team.code
        }

        let crossMatches = crossLeagueMatches.filter(isThisTeam)
        var seen = Set<String>()
        let merged = (leagueMatches + crossMatches).filter { seen.insert($0.id).inserted }

        let completed = merged.filter { isThisTeam($0) && $0.state == .completed }
            .sorted { $0.startTime > $1.startTime }

        recentMatches = Array(completed.prefix(30))
        h2hRecords = buildH2H(from: completed.filter { $0.league.id == league.id })
    }

    private func buildH2H(from matches: [Match]) -> [H2HRecord] {
        var dict: [String: H2HRecord] = [:]
        for match in matches {
            let isTeamA = match.teamA.id == team.id || match.teamA.code == team.code
            let opponent = isTeamA ? match.teamB : match.teamA
            let myScore  = isTeamA ? match.scoreA : match.scoreB
            let oppScore = isTeamA ? match.scoreB : match.scoreA
            let key = opponent.id.isEmpty ? opponent.code : opponent.id
            var record = dict[key] ?? H2HRecord(opponent: opponent, wins: 0, losses: 0)
            if myScore > oppScore { record.wins += 1 } else { record.losses += 1 }
            dict[key] = record
        }
        return dict.values.sorted { $0.opponent.name < $1.opponent.name }
    }
}

private func roleOrder(_ role: String) -> Int {
    switch role.lowercased() {
    case "top":              return 0
    case "jungle":           return 1
    case "mid":              return 2
    case "bottom", "bot":    return 3
    case "support":          return 4
    default:                 return 5
    }
}
