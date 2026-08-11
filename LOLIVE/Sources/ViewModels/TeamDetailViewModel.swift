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

    /// 백필된 팀/리그 컨텍스트 전용 로딩 경로. `historicalMatches`(서버, getHistoricalYears/
    /// getHistoricalMatches Callable — LeagueDetailView+History와 동일한 데이터)에서 이 팀이
    /// 나온 과거 경기를 찾아 최근경기/상대전적을 채우고, 가장 최근 경기의 게임별 실제 출전
    /// 명단(Match.games, 백필 시점에 이미 저장돼 있음)에서 선수단을 뽑는다 — Riot 실시간 API는
    /// 이 합성 ID를 모르니 호출하지 않는다.
    private func loadFromHistoricalData() async {
        let hadCache = preloadFromCache()
        isLoading = !hadCache
        loadFailed = false
        defer { isLoading = false }

        func isThisTeam(_ m: Match) -> Bool {
            m.teamA.id == team.id || m.teamA.code == team.code ||
            m.teamB.id == team.id || m.teamB.code == team.code
        }

        let years = await FirebaseHistoricalService.fetchYears(leagueName: league.name)
        var teamMatches: [Match] = []
        for year in years.sorted(by: >).prefix(3) {
            let matches = await FirebaseHistoricalService.fetchMatches(leagueName: league.name, year: year)
            teamMatches = matches.filter(isThisTeam)
            if !teamMatches.isEmpty { break }
        }

        #if DEBUG
        teamDetailLogger.debug("[TeamDetail] 백필 경로 — league.name=\(self.league.name) years=\(years) 매칭된 경기=\(teamMatches.count)")
        #endif

        guard !teamMatches.isEmpty else {
            if !hadCache { loadFailed = true }
            return
        }

        applyMatches(teamMatches)
        await loadRosterFromHistoricalMatch()
    }

    /// 가장 최근(연도 내 마지막 게임 번호) 백필 경기의 실제 출전 명단으로 선수단을 채운다.
    /// 백필 데이터는 "그 경기에 실제로 뛴 5명"이 확정값이라 현재 라이브 로스터처럼 주전/후보를
    /// 역산할 필요가 없다. 백필 소스(Match.games)엔 선수 이미지 URL이 없어서, Leaguepedia에서
    /// 별도로 조회한다 — 로스터가 그 경기 시점 이후로 안 바뀌는 한 이미지도 그대로라 7일 디스크
    /// 캐시가 재진입마다 그대로 재사용됨(선수당 최초 1회만 실제 네트워크 요청).
    private func loadRosterFromHistoricalMatch() async {
        guard let lastMatch = recentMatches.first,
              let games = lastMatch.games,
              let lastGame = games.max(by: { $0.number < $1.number })
        else { return }

        let myPlayers = lastGame.blueTeamId == team.id ? lastGame.bluePlayers : lastGame.redPlayers
        guard !myPlayers.isEmpty else { return }

        let basePlayers = myPlayers.map {
            Player(id: "\($0.participantId)", summonerName: $0.summonerName, firstName: nil, lastName: nil,
                   role: $0.role, imageURL: nil, teamId: team.id, teamCode: team.code)
        }

        let oracleElixir = OracleElixirService.shared
        let imageURLs: [Int: URL] = await withTaskGroup(of: (Int, URL?).self) { group in
            for (idx, player) in basePlayers.enumerated() {
                group.addTask { (idx, await oracleElixir.fetchPlayerImageURL(summonerName: player.summonerName)) }
            }
            var results: [Int: URL] = [:]
            for await (idx, url) in group where url != nil {
                results[idx] = url
            }
            return results
        }

        players = basePlayers.enumerated().map { idx, player in
            Player(id: player.id, summonerName: player.summonerName, firstName: player.firstName,
                   lastName: player.lastName, role: player.role,
                   imageURL: imageURLs[idx]?.absoluteString, teamId: player.teamId, teamCode: player.teamCode)
        }.sorted { roleOrder($0.role) < roleOrder($1.role) }
    }

    /// 최근 완료 경기의 마지막 게임 참가자 명단으로 "현재 주전"을 역산한다. 방금 끝난 경기는
    /// 시리즈 상태(`match.state`)만 completed로 먼저 반영되고 게임별 상세(`getEventDetails`의
    /// `games[].state`)는 Riot이 뒤늦게 채워주는 지연이 실제로 있어서(실측: LPL AL 팀에서
    /// 최신 경기가 games 전부 unstarted로 남아있는 채로 발견함), 가장 최근 경기 하나만 보면
    /// 주전 판별이 종종 실패한다. 성공할 때까지 최근 5경기까지 순서대로 시도한다.
    private func loadCurrentStarters() async {
        for match in recentMatches.prefix(5) {
            guard let detail = try? await service.fetchEventDetails(matchId: match.id),
                  let lastGame = detail.games.last(where: { $0.state == .completed })
            else { continue }

            let isTeamA = match.teamA.id == team.id || match.teamA.code == team.code
            let myEsportsId = isTeamA ? detail.teamAEsportsId : detail.teamBEsportsId
            guard let window = try? await liveStatsService.fetchGameWindow(gameId: lastGame.gameId, startingTime: nil)
            else { continue }

            // blue/red 배정은 반드시 window 자기 자신의 blueTeamId/redTeamId로 판단해야 한다 —
            // getEventDetails(lastGame)와 LiveStats(window)가 같은 게임인데도 서로 다른 blue/red
            // 배정을 준 사례를 실측으로 확인함(LPL JDG: lastGame은 LGD=blue/JDG=red라는데 window는
            // JDG=blue/LGD=red). lastGame 기준으로 판단하면 window에서 상대팀 선수를 골라오게 된다.
            let myPlayers = window.blueTeamId == myEsportsId ? window.bluePlayers : window.redPlayers
            guard !myPlayers.isEmpty else { continue }

            let matched = matchAgainstRoster(myPlayers)
            // 매칭이 0명이면 blue/red 판정이 실제로 틀렸거나(다른 팀 명단을 받아온 경우) 게임
            // 상세가 아직 안 채워진 것 — 다음 최근 경기로 재시도(이 for 루프가 이미 그 역할).
            guard !matched.isEmpty else { continue }
            currentStarterNames = matched
            return
        }
    }

    /// LiveStats API의 소환사명 표기가 리그마다 다르다(실측 확인) — LCK는 "T1 Oner"처럼 팀 코드
    /// 뒤에 공백을 두지만, LPL은 "BLGKnight"처럼 공백 없이 그대로 붙인다. 특정 구분자를 가정하고
    /// 접두사를 "제거"하려 하면 리그마다 깨지므로, 대신 이미 알고 있는 로스터 소환사명이 window
    /// 이름의 **접미사**로 포함되는지를 직접 검사한다 — 구분자 형식과 무관하게 안전하다.
    private func matchAgainstRoster(_ windowPlayers: [PlayerStats]) -> Set<String> {
        let windowNames = windowPlayers.map {
            $0.summonerName.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "")
        }
        var result: Set<String> = []
        for player in players {
            let rosterName = player.summonerName.trimmingCharacters(in: .whitespaces).lowercased()
            let rosterNameNoSpace = rosterName.replacingOccurrences(of: " ", with: "")
            guard !rosterNameNoSpace.isEmpty else { continue }
            if windowNames.contains(where: { $0 == rosterNameNoSpace || $0.hasSuffix(rosterNameNoSpace) }) {
                result.insert(rosterName)
            }
        }
        return result
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
