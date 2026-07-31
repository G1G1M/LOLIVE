//
//  TournamentDetailViewModel.swift
//  LOLIVE
//

import Foundation
import Observation

@MainActor
@Observable
final class TournamentDetailViewModel {

    // MARK: - Models

    struct DateGroup: Identifiable {
        let id: String          // "yyyy-MM-dd"
        let date: Date
        let matches: [Match]    // 해당 날짜 경기 (시간 오름차순)
    }

    // MARK: - Properties

    var tournaments: [Tournament] = []
    var selectedTournamentId: String = ""
    var selectedRound: String? = nil
    var allMatches: [Match] = []
    var isLoading = false
    var isLoadingHistoricalMatches = false  // 과거 연도 탭 선택 시 경기 로딩 표시
    var loadFailed = false

    private var historicalYearSet: Set<Int> = []  // Leaguepedia에 존재하는 연도 집합

    // MARK: - Computed: Tournament

    var selectedTournament: Tournament? {
        tournaments.first { $0.id == selectedTournamentId }
    }

    var selectedYear: String {
        String(selectedTournament?.startDate.prefix(4) ?? "")
    }

    var hasTournamentStarted: Bool {
        guard let t = selectedTournament else { return false }
        // synthetic_ 엔트리는 항상 시작된 것으로 취급
        if t.id.hasPrefix("synthetic_") { return true }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let start = fmt.date(from: t.startDate) else { return true }
        return Date() >= start
    }

    // MARK: - Computed: Matches for selected tournament

    var tournamentMatches: [Match] {
        guard let t = selectedTournament else { return [] }

        if t.id.hasPrefix("synthetic_") {
            // 연도 전체 커버
            let year = t.id.replacingOccurrences(of: "synthetic_", with: "")
            return allMatches.filter {
                String(Calendar.current.component(.year, from: $0.startTime)) == year
            }
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let start = fmt.date(from: t.startDate) else { return [] }
        if t.endDate.isEmpty {
            // endDate 없음 = 진행 중 토너먼트 → 시작일 이후 경기 전체 포함
            return allMatches.filter { $0.startTime >= start }
        }
        guard let end = fmt.date(from: t.endDate) else { return [] }
        let endExtended = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        return allMatches.filter { $0.startTime >= start && $0.startTime < endExtended }
    }

    // MARK: - Computed: Rounds (결승 → 8강 → 플레이인 순서)

    var availableRounds: [String] {
        let names = Array(Set(tournamentMatches.compactMap { $0.blockName }))
        return names.sorted { roundOrder($0) > roundOrder($1) }   // 내림차순: 결승 먼저
    }

    // MARK: - Computed: 날짜별 그룹 (최신 날짜 먼저)

    var selectedRoundDateGroups: [DateGroup] {
        // round 없으면 전체 경기 표시 (blockName 없는 과거 데이터 대응)
        let matches: [Match]
        if let round = selectedRound {
            matches = tournamentMatches.filter { $0.blockName == round }
        } else {
            matches = tournamentMatches
        }
        let cal = Calendar.current
        let byDay = Dictionary(grouping: matches) { cal.startOfDay(for: $0.startTime) }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return byDay.map { date, dayMatches in
            DateGroup(
                id: fmt.string(from: date),
                date: date,
                matches: dayMatches.sorted { $0.startTime < $1.startTime }
            )
        }.sorted { $0.date > $1.date }   // 최신 날짜 먼저
    }

    // MARK: - Private

    private let league: League
    private let service: RiotEsportsServiceProtocol
    private var historicalLoadTask: Task<Void, Never>?

    init(league: League, service: RiotEsportsServiceProtocol = RiotEsportsService()) {
        self.league = league
        self.service = service
    }

    // MARK: - Public

    func load() async {
        guard !isLoading && allMatches.isEmpty else { return }
        isLoading = true
        loadFailed = false

        async let tournamentsTask = service.fetchTournaments(leagueId: league.id)
        async let matchesTask     = service.fetchAllSchedule(league: league)

        let tournamentsFetch = try? await tournamentsTask
        let riotMatches      = (try? await matchesTask) ?? []

        if tournamentsFetch == nil && riotMatches.isEmpty {
            isLoading = false
            loadFailed = true
            return
        }

        let fetched = tournamentsFetch ?? []

        allMatches  = riotMatches
        tournaments = buildTournamentList(apiTournaments: fetched, matches: allMatches)

        let defaultT = activeTournament(from: fetched) ?? tournaments.first
        if let t = defaultT { selectedTournamentId = t.id }
        selectedRound = availableRounds.first
        isLoading = false  // Riot API 데이터로 즉시 화면 표시

        // 현재 토너먼트 완료 경기 백그라운드 프리로드
        for match in tournamentMatches.filter({ $0.state == .completed }).prefix(MatchDetailViewModel.preloadCount) {
            MatchDetailViewModel.preload(match: match)
        }

        // Phase 2: Leaguepedia에서 연도 목록만 가져와 탭 즉시 추가 (경기 데이터 제외)
        let riotYearCounts = Dictionary(
            grouping: riotMatches,
            by: { Calendar.current.component(.year, from: $0.startTime) }
        ).mapValues { $0.count }
        let fullyRiotYears = Set(riotYearCounts.filter { $0.value >= 20 }.keys)

        let lpYears = await LeaguepediaService.shared.historicalYears(for: league)
        guard !lpYears.isEmpty else { return }

        // Riot API가 완전히 커버하지 않는 연도만 탭 추가
        let existingYears = Set(tournaments.compactMap { t -> Int? in
            if t.id.hasPrefix("synthetic_") {
                return Int(t.id.replacingOccurrences(of: "synthetic_", with: ""))
            }
            return Int(String(t.startDate.prefix(4)))
        })
        let newYears = Set(lpYears).subtracting(fullyRiotYears).subtracting(existingYears)
        if !newYears.isEmpty {
            let synthetics = newYears.map { year in
                Tournament(id: "synthetic_\(year)", slug: "synthetic_\(year)",
                           startDate: "\(year)-01-01", endDate: "\(year)-12-31")
            }
            tournaments = (tournaments + synthetics).sorted { $0.startDate > $1.startDate }
        }
        historicalYearSet = Set(lpYears).subtracting(fullyRiotYears)

        // Phase 2b: 캐시된 과거 경기 데이터 즉시 로드 (재진입 시 데이터 유지)
        for year in historicalYearSet {
            let cached = await LeaguepediaService.shared.fetchMatchesFromCacheOnly(for: league, year: year)
            guard !cached.isEmpty else { continue }
            let unique = deduplicateAgainstRiot(cached, riotMatches: riotMatches)
            if !unique.isEmpty { allMatches.append(contentsOf: unique) }
        }

        // Phase 3: Riot API에 경기가 일부만 있는 연도 보완 (예: MSI 2023)
        let partialYears = Set(riotYearCounts.filter { $0.value > 0 && $0.value < 20 }.keys)
            .intersection(Set(lpYears))
        for year in partialYears {
            let lpMatches = await LeaguepediaService.shared.fetchMatches(for: league, year: year)
            guard !lpMatches.isEmpty else { continue }
            let unique = deduplicateAgainstRiot(lpMatches, riotMatches: riotMatches)
            if !unique.isEmpty { allMatches.append(contentsOf: unique) }
        }
    }

    func selectTournament(_ tournament: Tournament) {
        selectedTournamentId = tournament.id
        selectedRound = availableRounds.first

        // 과거 연도 탭 선택 시 해당 연도 경기 데이터 lazy load
        guard tournament.id.hasPrefix("synthetic_"),
              let year = Int(tournament.id.replacingOccurrences(of: "synthetic_", with: "")),
              historicalYearSet.contains(year),
              !allMatches.contains(where: {
                  Calendar.current.component(.year, from: $0.startTime) == year
              })
        else { return }
        historicalLoadTask?.cancel()
        isLoadingHistoricalMatches = true
        historicalLoadTask = Task { await loadHistoricalYear(year) }
    }

    private func loadHistoricalYear(_ year: Int) async {
        let matches = await LeaguepediaService.shared.fetchMatches(for: league, year: year)
        guard !matches.isEmpty else {
            isLoadingHistoricalMatches = false
            return
        }
        allMatches.append(contentsOf: matches)
        selectedRound = availableRounds.first
        isLoadingHistoricalMatches = false
    }

    private func deduplicateAgainstRiot(_ lpMatches: [Match], riotMatches: [Match]) -> [Match] {
        let cal = Calendar.current
        var sigs = Set<String>()
        for m in riotMatches {
            let d = Int(cal.startOfDay(for: m.startTime).timeIntervalSince1970)
            let c = [String(m.teamA.code.lowercased().prefix(3)),
                     String(m.teamB.code.lowercased().prefix(3))].sorted()
            sigs.insert("\(d)_\(c[0])_\(c[1])")
        }
        return lpMatches.filter { m in
            let d = Int(cal.startOfDay(for: m.startTime).timeIntervalSince1970)
            let c = [String(m.teamA.code.lowercased().prefix(3)),
                     String(m.teamB.code.lowercased().prefix(3))].sorted()
            return !sigs.contains("\(d)_\(c[0])_\(c[1])")
        }
    }

    // MARK: - Private Helpers

    /// API 토너먼트 목록 정리:
    /// - 경기 데이터가 있는 연도만 포함 (빈 과거 연도 제외)
    /// - 아직 시작 전인 미래 토너먼트는 유지 (시작 전 화면 표시용)
    /// - 경기 데이터는 있지만 API 토너먼트 항목이 없는 연도는 synthetic 항목으로 보완
    private func buildTournamentList(apiTournaments: [Tournament], matches: [Match]) -> [Tournament] {
        let coveredYears = Set(apiTournaments.map { String($0.startDate.prefix(4)) })
        let cal = Calendar.current
        let matchYears = Set(matches.map { String(cal.component(.year, from: $0.startTime)) })
        let missingYears = matchYears.subtracting(coveredYears)

        let synthetic = missingYears.map { year in
            Tournament(id: "synthetic_\(year)", slug: "synthetic_\(year)",
                       startDate: "\(year)-01-01", endDate: "\(year)-12-31")
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()

        return (apiTournaments + synthetic)
            .sorted { $0.startDate > $1.startDate }
            .filter { tournament in
                // 미래 토너먼트는 항상 포함
                if let start = fmt.date(from: tournament.startDate), start > now {
                    return true
                }
                // 과거/현재는 경기 데이터가 있을 때만 포함
                return !matchesFor(tournament: tournament, in: matches).isEmpty
            }
    }

    private func matchesFor(tournament: Tournament, in matches: [Match]) -> [Match] {
        if tournament.id.hasPrefix("synthetic_") {
            let year = tournament.id.replacingOccurrences(of: "synthetic_", with: "")
            return matches.filter {
                String(Calendar.current.component(.year, from: $0.startTime)) == year
            }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let start = fmt.date(from: tournament.startDate) else { return [] }
        if tournament.endDate.isEmpty {
            return matches.filter { $0.startTime >= start }
        }
        guard let end = fmt.date(from: tournament.endDate) else { return [] }
        let endExtended = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        return matches.filter { $0.startTime >= start && $0.startTime < endExtended }
    }

    private func roundOrder(_ name: String) -> Int {
        let s = name.lowercased()
        // 한국어
        if s.contains("플레이-인") || s.contains("플레이인")            { return 0 }
        if s.contains("스위스") || s.contains("그룹 스테이지")           { return 10 }
        if s.contains("그룹")                                          { return 11 }
        if s == "16강"                                                  { return 20 }
        if s == "8강"                                                   { return 21 }
        if s == "4강"                                                   { return 22 }
        if s.contains("그랜드 파이널")                                   { return 24 }
        if s.contains("결승")                                          { return 23 }
        // 영어
        if s.contains("play-in") || s.contains("playin")              { return 0 }
        if s.contains("swiss") || s.contains("group stage")           { return 10 }
        if s.contains("group")                                         { return 11 }
        if s.contains("week") || s.hasPrefix("day")                    { return 12 }
        if s.contains("round of 16")                                   { return 20 }
        if s.contains("round of 8") || s.contains("quarter")           { return 21 }
        if s.contains("semi")                                          { return 22 }
        if s.contains("grand final")                                   { return 24 }
        if s.contains("final")                                         { return 23 }
        if s.contains("playoff") || s.contains("knockout") ||
           s.contains("bracket stage") || s.contains("elimination")    { return 19 }
        if s.contains("bracket")                                       { return 20 }
        return 15
    }
}
