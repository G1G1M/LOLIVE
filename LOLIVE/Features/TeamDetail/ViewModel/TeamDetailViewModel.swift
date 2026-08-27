//
//  TeamDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation
import os


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

    var teamStats: TeamSeasonStats? = nil
    var isLoadingTeamStats = false
    var availableSeasons: [OESeasonOption] = []
    var selectedSeasonId: String? = nil

    /// 최근 완료 경기에 실제로 출전한 선수(정규화된 소환사명) — 포지션당 여러 명이 등록돼
    /// 있는 로스터에서 "지금 실제로 뛰는 선수"를 구분하는 용도. Riot의 getTeams 응답 자체엔
    /// 주전/후보 구분 필드가 없어서(실측 확인함), 가장 최근 완료 경기의 실제 출전 명단으로
    /// 역산한다. 못 구하면 빈 Set — 이 경우 화면은 구분 없이 기존처럼 전체 로스터를 보여준다.
    var currentStarterNames: Set<String> = []

    /// 분리된 extension 파일에서도 쓰도록 타입 소속으로 둔다.
    nonisolated static let teamDetailLogger = Logger(subsystem: "com.lolive", category: "TeamDetail")

    let team: Team
    var league: League
    let service: RiotEsportsServiceProtocol
    let liveStatsService: LiveStatsServiceProtocol
    var crossLeagueMatches: [Match] = []

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

    /// 과거 시즌 백필 데이터(oe.datalisk.io/Leaguepedia 경유)로 생성된 팀/리그 ID인지 판별.
    /// MatchDetailViewModel.isBackfilledMatchId와 동일한 접두사 규칙.
    nonisolated static func isBackfilledId(_ id: String) -> Bool {
        id.hasPrefix("oe_") || id.hasPrefix("lp_")
    }

    func load() async {
        // 백필된 과거 기록 경기(oe_/lp_ 접두사 ID)에서 진입한 경우 — 이 팀/리그 ID는 Riot 실시간
        // API가 모르는 합성 ID라 실시간 조회는 항상 빈 결과만 온다(실측 확인: roster=0, schedule=0).
        // 대신 이 경기 자체가 이미 백필 당시 게임별 실제 출전 선수 명단(Match.games)을 들고 있고,
        // 서버(historicalMatches)에도 같은 팀의 다른 과거 경기가 저장돼 있으므로 그걸로 채운다.
        if Self.isBackfilledId(team.id) || Self.isBackfilledId(league.id) {
            await loadFromHistoricalData()
            return
        }

        let hadCache = preloadFromCache()
        isLoading = !hadCache
        loadFailed = false
        defer { isLoading = false }

        #if DEBUG
        Self.teamDetailLogger.debug("[TeamDetail] load() 시작 — team.id=\(self.team.id) code=\(self.team.code) league.id=\(self.league.id) name=\(self.league.name) hadCache=\(hadCache)")
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
        Self.teamDetailLogger.debug("[TeamDetail] roster=\(rosterResult?.count ?? -1)명(err=\(rosterError ?? "없음")) schedule=\(matchResult?.count ?? -1)건(err=\(scheduleError ?? "없음"))")
        #endif

        if !hadCache && rosterResult == nil && matchResult == nil {
            loadFailed = true
            return
        }

        let roster = rosterResult ?? []
        players = roster.sorted { Self.roleOrder($0.role) < Self.roleOrder($1.role) }
        applyMatches(matchResult ?? [])
        await loadCurrentStarters()

        #if DEBUG
        Self.teamDetailLogger.debug("[TeamDetail] 최종 players=\(self.players.count) recentMatches=\(self.recentMatches.count) h2h=\(self.h2hRecords.count) starters=\(self.currentStarterNames.count)")
        #endif

        // 로스터/최근경기와 무관한 별도 소스(Oracle's Elixir)라 fire-and-forget으로 뒤에서
        // 채운다 — 여기서 기다리면 이 소스가 느리거나 실패할 때 위 핵심 데이터 표시까지
        // 같이 늦어질 위험이 있다(선수 탭에서 겪었던 것과 같은 종류의 문제).
        Task { await loadTeamStats() }
    }

    func preloadFromCache() -> Bool {
        var hadAny = false
        if let roster: [Player] = AppDiskCache.get(.roster(teamId: team.id)) {
            players = roster.sorted { Self.roleOrder($0.role) < Self.roleOrder($1.role) }
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
        // leagueMatches는 이미 이 팀의 홈 리그(league.id) 하나로 조회 범위가 좁혀져 있어서, 그
        // 리그 안에서 팀 코드가 겹칠 일이 없다 — 코드 폴백이 안전하다(Riot 스케줄 API가 팀 id를
        // null로 주는 경우가 흔해서, id만 보면 같은 팀인데도 매칭에 실패하는 걸 막아준다).
        func isThisTeam(_ m: Match) -> Bool {
            m.teamA.id == team.id || m.teamA.code == team.code ||
            m.teamB.id == team.id || m.teamB.code == team.code
        }

        // crossLeagueMatches는 여러 대회가 섞여 들어오는데(Today 화면의 전체 리그 매치 등),
        // 같은 조직의 1군/2군 팀이 같은 코드를 공유하는 경우가 있다(실측 확인: LCK 챌린저스에도
        // "DK"/"KT" 코드 팀이 따로 있음 — 팀 id는 서로 다름). 코드로 매칭하면 2군 경기가 1군
        // "최근 경기"에 섞여 들어와서 주전 판별까지 2군 선수로 잘못 나오는 버그가 있었다 —
        // 크로스리그 경기는 반드시 실제 팀 id가 일치할 때만 인정한다.
        func isThisTeamCrossLeague(_ m: Match) -> Bool {
            m.teamA.id == team.id || m.teamB.id == team.id
        }

        let crossMatches = crossLeagueMatches.filter(isThisTeamCrossLeague)
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

extension TeamDetailViewModel {

    /// 선수단 정렬 순서 — 탑/정글/미드/원딜/서폿.
    static func roleOrder(_ role: String) -> Int {
        switch role.lowercased() {
        case "top":              return 0
        case "jungle":           return 1
        case "mid":              return 2
        case "bottom", "bot":    return 3
        case "support":          return 4
        default:                 return 5
        }
    }
}
