//
//  ViewModelTests.swift
//  LOLIVETests
//
//  TodayViewModel/StandingsViewModel/TeamDetailViewModel의 핵심 분류·집계 로직 테스트.
//  네트워크가 필요 없는 순수 계산 함수만 internal로 열어서 직접 검증한다.
//

import Testing
import Foundation
@testable import LOLIVE

// MARK: - 공통 픽스처 헬퍼

private enum Fixture {
    // TodayViewModel과 동일한 캘린더(한국 시간 기준 자정)를 써야 날짜 경계 테스트가
    // 테스트 실행 시각(특히 자정 근처)에 흔들리지 않는다. Date()에 상대적인 오프셋 대신
    // "오늘 자정"을 고정 기준점으로 삼는다.
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal
    }()
    private static var todayStart: Date { calendar.startOfDay(for: Date()) }

    /// 오늘(한국시간) 특정 시각. 기본 10시 — 실행 시각과 무관하게 항상 "오늘" 범위 안.
    static func today(hour: Int = 10) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: todayStart)!
    }
    static func tomorrow(hour: Int = 10) -> Date {
        calendar.date(byAdding: .day, value: 1, to: today(hour: hour))!
    }
    static func daysAgo(_ days: Int, hour: Int = 10) -> Date {
        calendar.date(byAdding: .day, value: -days, to: today(hour: hour))!
    }

    static let lck = League(id: "lck", slug: "lck", name: "LCK", region: "한국", imageURL: nil)
    static let kespa = League(id: "kespa", slug: "kespa_cup", name: "KeSPA Cup", region: "한국", imageURL: nil)
    static let worlds = League(id: "worlds", slug: "worlds", name: "Worlds", region: "국제 대회", imageURL: nil)

    static let t1 = Team(id: "T1", name: "T1", code: "T1", imageURL: nil)
    static let gen = Team(id: "GEN", name: "Gen.G", code: "GEN", imageURL: nil)
    static let hle = Team(id: "HLE", name: "Hanwha Life", code: "HLE", imageURL: nil)

    static func match(
        id: String, league: League = lck,
        teamA: Team = t1, teamB: Team = gen,
        scoreA: Int = 0, scoreB: Int = 0,
        startTime: Date, state: MatchState
    ) -> Match {
        Match(id: id, league: league, teamA: teamA, teamB: teamB,
              scoreA: scoreA, scoreB: scoreB, startTime: startTime, state: state)
    }

    static func standing(team: Team, wins: Int, losses: Int, rank: Int, group: String? = nil) -> Standing {
        Standing(team: team, wins: wins, losses: losses, rank: rank,
                 winRate: wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses),
                 group: group)
    }
}

// MARK: - TodayViewModel.classify

@MainActor
@Suite("TodayViewModel.classify")
struct TodayViewModelClassifyTests {

    @Test func 오늘_예정된_경기는_todayMatches로_분류된다() {
        let vm = TodayViewModel()
        let match = Fixture.match(id: "m1", startTime: Fixture.today(), state: .unstarted)
        vm.classify(matches: [match])
        #expect(vm.todayMatches.map(\.id) == ["m1"])
        #expect(vm.upcomingMatches.isEmpty)
        #expect(vm.completedMatches.isEmpty)
    }

    @Test func 이미_시작했지만_진행중인_오늘_경기도_todayMatches에_남는다() {
        // 라이브 폴링 중 fetchLive()에서만 빠지는 순간에도 화면에서 사라지지 않아야 하는 핵심 케이스
        let vm = TodayViewModel()
        let match = Fixture.match(id: "m2", startTime: Fixture.today(hour: 0), state: .inProgress)
        vm.classify(matches: [match])
        #expect(vm.todayMatches.map(\.id) == ["m2"])
    }

    @Test func 내일_이후_경기는_upcomingMatches로_분류된다() {
        let vm = TodayViewModel()
        let match = Fixture.match(id: "m3", startTime: Fixture.tomorrow(), state: .unstarted)
        vm.classify(matches: [match])
        #expect(vm.upcomingMatches.map(\.id) == ["m3"])
        #expect(vm.todayMatches.isEmpty)
    }

    @Test func 완료된_경기는_completedMatches로_분류된다() {
        let vm = TodayViewModel()
        let match = Fixture.match(id: "m4", startTime: Fixture.today(hour: 2), state: .completed)
        vm.classify(matches: [match])
        #expect(vm.completedMatches.map(\.id) == ["m4"])
    }

    @Test func 십일전_완료경기는_5일_컷오프_밖이라_제외된다() {
        let vm = TodayViewModel()
        let match = Fixture.match(id: "m5", startTime: Fixture.daysAgo(10), state: .completed)
        vm.classify(matches: [match])
        #expect(vm.completedMatches.isEmpty)
    }

    @Test func 완료경기는_최신순으로_정렬된다() {
        let vm = TodayViewModel()
        let older = Fixture.match(id: "old", startTime: Fixture.daysAgo(2), state: .completed)
        let newer = Fixture.match(id: "new", startTime: Fixture.today(hour: 2), state: .completed)
        vm.classify(matches: [older, newer])
        #expect(vm.completedMatches.map(\.id) == ["new", "old"])
    }
}

// MARK: - TodayViewModel.markCompleted

@MainActor
@Suite("TodayViewModel.markCompleted")
struct TodayViewModelMarkCompletedTests {

    @Test func todayMatches에서_제거되고_completedMatches_맨_앞에_들어간다() {
        let vm = TodayViewModel()
        let live = Fixture.match(id: "live1", startTime: Fixture.today(hour: 0), state: .inProgress)
        vm.classify(matches: [live])
        #expect(vm.todayMatches.map(\.id) == ["live1"])

        vm.markCompleted(live)

        #expect(vm.todayMatches.isEmpty)
        #expect(vm.completedMatches.first?.id == "live1")
        #expect(vm.completedMatches.first?.state == .completed)
    }

    @Test func upcomingMatches에_있어도_제거된다() {
        let vm = TodayViewModel()
        let match = Fixture.match(id: "up1", startTime: Fixture.tomorrow(), state: .inProgress)
        vm.classify(matches: [match])
        #expect(vm.upcomingMatches.map(\.id) == ["up1"])

        vm.markCompleted(match)
        #expect(vm.upcomingMatches.isEmpty)
    }

    @Test func 이미_completedMatches에_있으면_중복_삽입하지_않는다() {
        let vm = TodayViewModel()
        let match = Fixture.match(id: "dup1", startTime: Fixture.today(hour: 0), state: .completed)
        vm.classify(matches: [match])
        #expect(vm.completedMatches.count == 1)

        vm.markCompleted(match)
        #expect(vm.completedMatches.count == 1)
    }
}

// MARK: - StandingsViewModel.applyGD

@MainActor
@Suite("StandingsViewModel.applyGD")
struct StandingsViewModelApplyGDTests {

    @Test func 개별_승패가_있으면_Riot_순위를_그대로_쓰고_GD만_채운다() {
        let vm = StandingsViewModel()
        let standings = [
            Fixture.standing(team: Fixture.t1, wins: 5, losses: 1, rank: 1),
            Fixture.standing(team: Fixture.gen, wins: 3, losses: 3, rank: 2),
        ]
        let schedule = [
            Fixture.match(id: "s1", scoreA: 2, scoreB: 0, startTime: Fixture.daysAgo(1), state: .completed),
        ]
        let result = vm.applyGD(standings, schedule: schedule)

        #expect(result.map(\.rank) == [1, 2])
        #expect(result.first { $0.team.id == "T1" }?.gameWins == 2)
        #expect(result.first { $0.team.id == "T1" }?.gameLosses == 0)
    }

    @Test func 케스파컵처럼_전원_0승0패면_완료경기로_재계산한다() {
        let vm = StandingsViewModel()
        // Riot이 두 팀을 동률 1위로 묶어 내려주는 상황 (실제 관측된 케이스)
        let standings = [
            Fixture.standing(team: Fixture.t1, wins: 0, losses: 0, rank: 1),
            Fixture.standing(team: Fixture.gen, wins: 0, losses: 0, rank: 1),
            Fixture.standing(team: Fixture.hle, wins: 0, losses: 0, rank: 1),
        ]
        let schedule = [
            Fixture.match(id: "k1", league: Fixture.kespa, teamA: Fixture.t1, teamB: Fixture.gen,
                          scoreA: 1, scoreB: 0, startTime: Fixture.daysAgo(2), state: .completed),
            Fixture.match(id: "k2", league: Fixture.kespa, teamA: Fixture.t1, teamB: Fixture.hle,
                          scoreA: 1, scoreB: 0, startTime: Fixture.daysAgo(1), state: .completed),
        ]
        let result = vm.applyGD(standings, schedule: schedule)

        let t1 = result.first { $0.team.id == "T1" }
        let gen = result.first { $0.team.id == "GEN" }
        let hle = result.first { $0.team.id == "HLE" }

        #expect(t1?.wins == 2 && t1?.losses == 0)
        #expect(gen?.wins == 0 && gen?.losses == 1)
        #expect(hle?.wins == 0 && hle?.losses == 1)
        #expect(t1?.rank == 1)
    }

    @Test func 완료경기가_없으면_재계산하지_않고_원본을_유지한다() {
        let vm = StandingsViewModel()
        let standings = [Fixture.standing(team: Fixture.t1, wins: 0, losses: 0, rank: 1)]
        let result = vm.applyGD(standings, schedule: [])
        #expect(result.first?.rank == 1)
        #expect(result.first?.wins == 0)
    }

    @Test func 그룹이_다르면_그룹별로_따로_순위가_매겨진다() {
        let vm = StandingsViewModel()
        let standings = [
            Fixture.standing(team: Fixture.t1, wins: 0, losses: 0, rank: 1, group: "알파조"),
            Fixture.standing(team: Fixture.gen, wins: 0, losses: 0, rank: 1, group: "오메가조"),
        ]
        let schedule = [
            Fixture.match(id: "g1", league: Fixture.kespa, teamA: Fixture.t1, teamB: Fixture.hle,
                          scoreA: 1, scoreB: 0, startTime: Fixture.daysAgo(2), state: .completed),
            Fixture.match(id: "g2", league: Fixture.kespa, teamA: Fixture.gen, teamB: Fixture.hle,
                          scoreA: 1, scoreB: 0, startTime: Fixture.daysAgo(1), state: .completed),
        ]
        let result = vm.applyGD(standings, schedule: schedule)
        // 각 팀이 자기 그룹 안에서 1위를 유지해야 한다 (그룹 간 랭크가 서로 간섭하지 않음)
        #expect(result.first { $0.team.id == "T1" }?.rank == 1)
        #expect(result.first { $0.team.id == "GEN" }?.rank == 1)
    }
}

// MARK: - TeamDetailViewModel.applyMatches

@MainActor
@Suite("TeamDetailViewModel.applyMatches")
struct TeamDetailViewModelApplyMatchesTests {

    @Test func 리그_경기만_있으면_상대전적_최근경기_둘_다_채워진다() {
        let vm = TeamDetailViewModel(team: Fixture.t1, league: Fixture.lck)
        let matches = [
            Fixture.match(id: "l1", teamA: Fixture.t1, teamB: Fixture.gen,
                          scoreA: 2, scoreB: 1, startTime: Fixture.daysAgo(1), state: .completed),
        ]
        vm.applyMatches(matches)

        #expect(vm.recentMatches.map(\.id) == ["l1"])
        #expect(vm.h2hRecords.first?.wins == 1)
        #expect(vm.h2hRecords.first?.losses == 0)
    }

    @Test func 교차리그_경기는_최근경기엔_포함되지만_상대전적엔_제외된다() {
        let vm = TeamDetailViewModel(team: Fixture.t1, league: Fixture.lck)
        vm.setCrossLeagueMatches([
            Fixture.match(id: "w1", league: Fixture.worlds, teamA: Fixture.t1, teamB: Fixture.hle,
                          scoreA: 3, scoreB: 2, startTime: Fixture.daysAgo(1), state: .completed),
        ])
        let lckMatches = [
            Fixture.match(id: "l2", league: Fixture.lck, teamA: Fixture.t1, teamB: Fixture.gen,
                          scoreA: 2, scoreB: 0, startTime: Fixture.daysAgo(2), state: .completed),
        ]
        vm.applyMatches(lckMatches)

        // 최근경기: 대회 상관없이 둘 다 포함, 최신순
        #expect(vm.recentMatches.map(\.id) == ["w1", "l2"])
        // 상대전적: 현재 리그(LCK) 경기만 — Worlds 상대(HLE)는 집계되지 않음
        #expect(vm.h2hRecords.contains { $0.opponent.id == "GEN" })
        #expect(!vm.h2hRecords.contains { $0.opponent.id == "HLE" })
    }

    @Test func 다른팀_경기는_교차리그_목록에_있어도_무시된다() {
        let vm = TeamDetailViewModel(team: Fixture.t1, league: Fixture.lck)
        vm.setCrossLeagueMatches([
            Fixture.match(id: "irrelevant", league: Fixture.worlds,
                          teamA: Fixture.gen, teamB: Fixture.hle,
                          startTime: Fixture.daysAgo(1), state: .completed),
        ])
        vm.applyMatches([])
        #expect(vm.recentMatches.isEmpty)
    }

    @Test func 동일_id_경기는_중복_집계되지_않는다() {
        let vm = TeamDetailViewModel(team: Fixture.t1, league: Fixture.lck)
        let shared = Fixture.match(id: "dup", teamA: Fixture.t1, teamB: Fixture.gen,
                                   scoreA: 2, scoreB: 0, startTime: Fixture.daysAgo(1), state: .completed)
        vm.setCrossLeagueMatches([shared])
        vm.applyMatches([shared])
        #expect(vm.recentMatches.count == 1)
    }
}
