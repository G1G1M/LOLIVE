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
    var loadFailed = false

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

    var availableRounds: [Match.RoundGroup] {
        Match.roundGroups(from: tournamentMatches)
    }

    // MARK: - Computed: 날짜별 그룹 (최신 날짜 먼저)

    var selectedRoundDateGroups: [DateGroup] {
        // round 없으면 전체 경기 표시 (blockName 없는 과거 데이터 대응)
        let matches: [Match]
        if let round = selectedRound, let group = availableRounds.first(where: { $0.label == round }) {
            matches = group.matches
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
        selectedRound = availableRounds.first?.label
        isLoading = false  // Riot API 데이터로 즉시 화면 표시

        // 현재 토너먼트 완료 경기 백그라운드 프리로드
        for match in tournamentMatches.filter({ $0.state == .completed }).prefix(MatchDetailViewModel.preloadCount) {
            MatchDetailViewModel.preload(match: match)
        }

        // Phase 2: 서버에 미리 백필된 과거 시즌 데이터로 보완 — LeagueDetailView+History(일반 리그
        // "기록" 탭)와 동일한 getHistoricalYears/getHistoricalMatches Callable 사용. Leaguepedia를
        // 실시간으로 직접 호출하지 않으므로 레이트리밋(분당 1회 추정) 없이 연도 전체를 한 번에
        // 병렬로 가져올 수 있다 — 예전엔 Leaguepedia 실시간 호출 + 연도 하나씩 탭을 눌러야만
        // lazy load되는 구조라 Worlds/MSI처럼 연도가 많은 대회에서 느리거나 레이트리밋에 걸렸음.
        guard let leagueName = LeaguepediaService.shared.leaguepediaName(for: league) else { return }
        let backfilledYears = await FirebaseHistoricalService.fetchYears(leagueName: leagueName)
        guard !backfilledYears.isEmpty else { return }

        let riotYearCounts = Dictionary(
            grouping: riotMatches,
            by: { Calendar.current.component(.year, from: $0.startTime) }
        ).mapValues { $0.count }
        let fullyRiotYears = Set(riotYearCounts.filter { $0.value >= 20 }.keys)
        // Riot API가 완전히 커버하는 연도는 제외, 그 외(전혀 없거나 일부만 있는 연도)는 전부 보완
        let neededYears = Set(backfilledYears).subtracting(fullyRiotYears)
        guard !neededYears.isEmpty else { return }

        let fetchedByYear: [[Match]] = await withTaskGroup(of: [Match].self) { group in
            for year in neededYears {
                group.addTask { await FirebaseHistoricalService.fetchMatches(leagueName: leagueName, year: year) }
            }
            var results: [[Match]] = []
            for await matches in group { results.append(matches) }
            return results
        }
        for serverMatches in fetchedByYear {
            let unique = deduplicateAgainstRiot(serverMatches, riotMatches: riotMatches)
            if !unique.isEmpty { allMatches.append(contentsOf: unique) }
        }

        // Riot API 토너먼트 항목이 아예 없는 연도만 synthetic 탭으로 보완(있는 연도는 실제
        // API 토너먼트 탭에 위에서 병합한 경기가 그대로 합쳐짐)
        let existingYears = Set(tournaments.compactMap { t -> Int? in
            if t.id.hasPrefix("synthetic_") {
                return Int(t.id.replacingOccurrences(of: "synthetic_", with: ""))
            }
            return Int(String(t.startDate.prefix(4)))
        })
        let newYears = neededYears.subtracting(existingYears)
        if !newYears.isEmpty {
            let synthetics = newYears.map { year in
                Tournament(id: "synthetic_\(year)", slug: "synthetic_\(year)",
                           startDate: "\(year)-01-01", endDate: "\(year)-12-31")
            }
            tournaments = (tournaments + synthetics).sorted { $0.startDate > $1.startDate }
        }
    }

    func selectTournament(_ tournament: Tournament) {
        selectedTournamentId = tournament.id
        selectedRound = availableRounds.first?.label
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
}
