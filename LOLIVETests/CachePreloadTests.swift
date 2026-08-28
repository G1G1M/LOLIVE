//
//  CachePreloadTests.swift
//  LOLIVETests
//
//  디스크 캐시 선로딩 경로 테스트.
//  앱 시작·화면 진입 시 메인 스레드를 막지 않으려고 이 읽기들을 nonisolated 함수로 뽑아
//  백그라운드에서 실행하는데, 뽑는 과정에서 원래 동작이 바뀌지 않았는지 고정한다.
//
//  실제 캐시 파일을 건드리지 않도록 리그·팀 id에 "test_" 접두사를 붙인 합성 값만 쓴다.
//

import Testing
import Foundation
@testable import LOLIVE

private enum CacheFixture {
    static func league(_ id: String) -> League {
        League(id: "test_\(id)", slug: id, name: id.uppercased(), region: "테스트", imageURL: nil)
    }

    static let teamA = Team(id: "test_A", name: "Team A", code: "TA", imageURL: nil)
    static let teamB = Team(id: "test_B", name: "Team B", code: "TB", imageURL: nil)

    static func match(id: String, league: League, daysAgo: Int, state: MatchState) -> Match {
        Match(id: id, league: league, teamA: teamA, teamB: teamB,
              scoreA: state == .completed ? 2 : 0, scoreB: state == .completed ? 1 : 0,
              startTime: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
              state: state)
    }

    /// 테스트가 쓴 캐시 파일만 정리한다.
    static func clearSchedules(_ leagues: [League]) {
        for l in leagues {
            AppDiskCache.clear(.schedule(leagueId: l.id))
            AppDiskCache.clear(.allSchedule(leagueId: l.id))
        }
    }
}

// MARK: - TodayViewModel

@Suite("TodayViewModel 캐시 선로딩")
struct TodayCachePreloadTests {

    @Test("리그별 스케줄 캐시를 전부 이어붙여 반환한다")
    func mergesEveryLeagueSchedule() {
        let a = CacheFixture.league("a"), b = CacheFixture.league("b")
        defer { CacheFixture.clearSchedules([a, b]) }

        AppDiskCache.set(.schedule(leagueId: a.id), value: [
            CacheFixture.match(id: "a1", league: a, daysAgo: 1, state: .completed),
            CacheFixture.match(id: "a2", league: a, daysAgo: -1, state: .unstarted),
        ])
        AppDiskCache.set(.schedule(leagueId: b.id), value: [
            CacheFixture.match(id: "b1", league: b, daysAgo: 2, state: .completed),
        ])

        let merged = TodayViewModel.readCachedSchedules(for: [a, b], stale: false)
        let ids = Set(merged.map(\.id))
        #expect(merged.count == 3)
        #expect(ids == ["a1", "a2", "b1"])
    }

    @Test("캐시가 없는 리그는 건너뛰고 나머지만 반환한다")
    func skipsLeaguesWithoutCache() {
        let a = CacheFixture.league("c"), missing = CacheFixture.league("d")
        defer { CacheFixture.clearSchedules([a, missing]) }

        AppDiskCache.set(.schedule(leagueId: a.id), value: [
            CacheFixture.match(id: "c1", league: a, daysAgo: 1, state: .completed),
        ])

        let merged = TodayViewModel.readCachedSchedules(for: [a, missing], stale: false)
        #expect(merged.map(\.id) == ["c1"])
    }

    @Test("리그가 하나도 캐시돼 있지 않으면 빈 배열")
    func emptyWhenNothingCached() {
        let missing = CacheFixture.league("e")
        defer { CacheFixture.clearSchedules([missing]) }
        #expect(TodayViewModel.readCachedSchedules(for: [missing], stale: false).isEmpty)
    }

    @Test("stale 경로도 같은 데이터를 읽는다")
    func stalePathReadsSameData() {
        let a = CacheFixture.league("f")
        defer { CacheFixture.clearSchedules([a]) }

        AppDiskCache.set(.schedule(leagueId: a.id), value: [
            CacheFixture.match(id: "f1", league: a, daysAgo: 3, state: .completed),
        ])

        let fresh = TodayViewModel.readCachedSchedules(for: [a], stale: false)
        let stale = TodayViewModel.readCachedSchedules(for: [a], stale: true)
        #expect(fresh.map(\.id) == stale.map(\.id))
    }
}

// MARK: - TeamDetailViewModel

@Suite("TeamDetailViewModel 캐시 선로딩")
struct TeamDetailCachePreloadTests {

    @Test("로스터·전체 스케줄을 둘 다 읽어온다")
    func readsRosterAndSchedule() {
        let league = CacheFixture.league("g")
        let team = CacheFixture.teamA
        defer {
            CacheFixture.clearSchedules([league])
            AppDiskCache.clear(.roster(teamId: team.id))
        }

        AppDiskCache.set(.roster(teamId: team.id), value: [
            Player(id: "p1", summonerName: "Mid", firstName: nil, lastName: nil,
                   role: "mid", imageURL: nil, teamId: team.id, teamCode: team.code),
        ])
        AppDiskCache.set(.allSchedule(leagueId: league.id), value: [
            CacheFixture.match(id: "g1", league: league, daysAgo: 1, state: .completed),
        ])

        let result = TeamDetailViewModel.readDiskPreload(teamId: team.id, leagueId: league.id)
        #expect(result?.roster?.count == 1)
        #expect(result?.allMatches?.map(\.id) == ["g1"])
    }

    @Test("둘 다 캐시가 없으면 nil")
    func nilWhenNothingCached() {
        let league = CacheFixture.league("h")
        defer { CacheFixture.clearSchedules([league]) }
        #expect(TeamDetailViewModel.readDiskPreload(teamId: "test_none", leagueId: league.id) == nil)
    }

    @Test("한쪽만 있어도 그쪽은 읽어온다")
    func readsPartialCache() {
        let league = CacheFixture.league("i")
        defer { CacheFixture.clearSchedules([league]) }

        AppDiskCache.set(.allSchedule(leagueId: league.id), value: [
            CacheFixture.match(id: "i1", league: league, daysAgo: 1, state: .completed),
        ])

        let result = TeamDetailViewModel.readDiskPreload(teamId: "test_none", leagueId: league.id)
        #expect(result?.roster == nil)
        #expect(result?.allMatches?.count == 1)
    }
}

// MARK: - SearchViewModel.results

@MainActor
@Suite("SearchViewModel.results")
struct SearchResultsTests {

    private static func player(_ name: String, id: String) -> Player {
        Player(id: id, summonerName: name, firstName: nil, lastName: nil,
               role: "mid", imageURL: nil, teamId: "t", teamCode: "T")
    }

    private static func makeVM(players: Int) -> SearchViewModel {
        let vm = SearchViewModel()
        let league = League(id: "L", slug: "l", name: "Alpha League", region: "한국", imageURL: nil)
        vm.allLeagues = [league]
        vm.allTeams = (0..<20).map {
            (team: Team(id: "team\($0)", name: "Alpha Team \($0)", code: "AT\($0)", imageURL: nil),
             league: league)
        }
        vm.allPlayers = (0..<players).map {
            (player: player("Alpha\($0)", id: "p\($0)"), league: league)
        }
        return vm
    }

    @Test("빈 검색어는 결과가 없다")
    func emptyQueryReturnsNothing() {
        #expect(Self.makeVM(players: 10).results(for: "   ").isEmpty)
    }

    @Test("종류별 개수 상한(리그 3·팀 10·선수 10)을 지킨다")
    func respectsPerCategoryLimits() {
        // lazy + prefix 로 바꾼 뒤에도 상한과 순서가 그대로여야 한다.
        let results = Self.makeVM(players: 500).results(for: "alpha")
        var leagues = 0, teams = 0, players = 0
        for r in results {
            switch r {
            case .league: leagues += 1
            case .team: teams += 1
            case .player: players += 1
            }
        }
        #expect(leagues == 1)   // 리그는 1개뿐
        #expect(teams == 10)
        #expect(players == 10)
    }

    @Test("결과는 리그 → 팀 → 선수 순서로 나온다")
    func keepsCategoryOrder() {
        let results = Self.makeVM(players: 50).results(for: "alpha")
        let kinds: [String] = results.map {
            switch $0 {
            case .league: return "league"
            case .team: return "team"
            case .player: return "player"
            }
        }
        #expect(kinds == Array(repeating: "league", count: 1)
                       + Array(repeating: "team", count: 10)
                       + Array(repeating: "player", count: 10))
    }

    @Test("매칭 안 되는 검색어는 빈 결과")
    func noMatch() {
        #expect(Self.makeVM(players: 50).results(for: "zzzz").isEmpty)
    }
}
