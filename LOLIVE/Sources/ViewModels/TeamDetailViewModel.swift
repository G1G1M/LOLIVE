//
//  TeamDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation
import os

private let teamDetailLogger = Logger(subsystem: "com.lolive", category: "TeamDetail")

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

    /// 최근 완료 경기에 실제로 출전한 선수(정규화된 소환사명) — 포지션당 여러 명이 등록돼
    /// 있는 로스터에서 "지금 실제로 뛰는 선수"를 구분하는 용도. Riot의 getTeams 응답 자체엔
    /// 주전/후보 구분 필드가 없어서(실측 확인함), 가장 최근 완료 경기의 실제 출전 명단으로
    /// 역산한다. 못 구하면 빈 Set — 이 경우 화면은 구분 없이 기존처럼 전체 로스터를 보여준다.
    var currentStarterNames: Set<String> = []

    private let team: Team
    private var league: League
    private let service: RiotEsportsServiceProtocol
    private let liveStatsService: LiveStatsServiceProtocol
    private var crossLeagueMatches: [Match] = []

    init(team: Team, league: League,
         service: RiotEsportsServiceProtocol = RiotEsportsService(),
         liveStatsService: LiveStatsServiceProtocol = LiveStatsService()) {
        self.team = team
        self.league = league
        self.service = service
        self.liveStatsService = liveStatsService
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

        #if DEBUG
        teamDetailLogger.debug("[TeamDetail] load() 시작 — team.id=\(self.team.id) code=\(self.team.code) league.id=\(self.league.id) name=\(self.league.name) hadCache=\(hadCache)")
        #endif

        async let rosterTask = service.fetchTeamRoster(teamId: team.id)
        // 15분짜리 오늘 기준 스케줄이 아니라, 과거 페이지까지 전부 훑는 전체 시즌 스케줄을 사용해야
        // 최근 맞대결이 없어도 상대 전적·최근 경기가 안정적으로 채워짐
        async let scheduleTask = service.fetchAllSchedule(league: league)

        var rosterError: String? = nil
        var scheduleError: String? = nil
        let rosterResult: [Player]?
        do { rosterResult = try await rosterTask } catch { rosterResult = nil; rosterError = "\(error)" }
        let matchResult: [Match]?
        do { matchResult = try await scheduleTask } catch { matchResult = nil; scheduleError = "\(error)" }

        #if DEBUG
        teamDetailLogger.debug("[TeamDetail] roster=\(rosterResult?.count ?? -1)명(err=\(rosterError ?? "없음")) schedule=\(matchResult?.count ?? -1)건(err=\(scheduleError ?? "없음"))")
        #endif

        if !hadCache && rosterResult == nil && matchResult == nil {
            loadFailed = true
            return
        }

        let roster = rosterResult ?? []
        players = roster.sorted { roleOrder($0.role) < roleOrder($1.role) }
        applyMatches(matchResult ?? [])
        await loadCurrentStarters()

        #if DEBUG
        teamDetailLogger.debug("[TeamDetail] 최종 players=\(self.players.count) recentMatches=\(self.recentMatches.count) h2h=\(self.h2hRecords.count) starters=\(self.currentStarterNames.count)")
        #endif
    }

    /// 가장 최근 완료 경기의 마지막 게임 참가자 명단으로 "현재 주전"을 역산한다.
    private func loadCurrentStarters() async {
        guard let lastMatch = recentMatches.first,
              let detail = try? await service.fetchEventDetails(matchId: lastMatch.id),
              let lastGame = detail.games.last(where: { $0.state == .completed })
        else { return }

        let isTeamA = lastMatch.teamA.id == team.id || lastMatch.teamA.code == team.code
        let myEsportsId = isTeamA ? detail.teamAEsportsId : detail.teamBEsportsId
        guard let window = try? await liveStatsService.fetchGameWindow(gameId: lastGame.gameId, startingTime: nil)
        else { return }

        let myPlayers = lastGame.blueTeamId == myEsportsId ? window.bluePlayers : window.redPlayers
        guard !myPlayers.isEmpty else { return }
        currentStarterNames = Set(myPlayers.map { normalizedName($0.summonerName) })
    }

    /// LiveStats API의 소환사명엔 "T1 Oner"처럼 팀 코드 접두사가 붙어 나오지만(실측 확인함),
    /// getTeams 로스터의 소환사명("Oner")엔 접두사가 없다 — 이 팀의 코드 접두사만 제거해서 맞춘다.
    private func normalizedName(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces).lowercased()
        let prefix = team.code.trimmingCharacters(in: .whitespaces).lowercased() + " "
        if n.hasPrefix(prefix) { n.removeFirst(prefix.count) }
        return n
    }

    private func preloadFromCache() -> Bool {
        var hadAny = false
        if let roster: [Player] = AppDiskCache.get(.roster(teamId: team.id)) {
            players = roster.sorted { roleOrder($0.role) < roleOrder($1.role) }
            hadAny = true
        }
        if let allMatches: [Match] = AppDiskCache.get(.allSchedule(leagueId: league.id)) {
            applyMatches(allMatches)
            hadAny = true
        }
        return hadAny
    }

    /// 현재 리그 전체 스케줄 + 교차 리그(국제 대회 등) 경기를 합쳐
    /// "최근 경기"는 대회 상관없이 전부, "상대 전적"은 현재 리그/대회 내 경기만으로 구성한다.
    func applyMatches(_ leagueMatches: [Match]) {
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
