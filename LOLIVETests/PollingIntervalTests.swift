//
//  PollingIntervalTests.swift
//  LOLIVETests
//
//  폴링 주기 계산 테스트.
//  라이브 경기가 없을 때도 30초마다 계속 두드리면 받을 것도 없이 통신만 일어나므로,
//  상황에 따라 주기를 늘린다. 늘리는 김에 "곧 시작할 경기"를 놓치면 안 되는 게 핵심이라
//  경계 조건을 고정한다.
//

import Testing
import Foundation
@testable import LOLIVE

private enum PollFixture {
    static let league = League(id: "L", slug: "l", name: "LCK", region: "한국", imageURL: nil)
    static let teamA = Team(id: "A", name: "A", code: "A", imageURL: nil)
    static let teamB = Team(id: "B", name: "B", code: "B", imageURL: nil)

    static func match(minutesFromNow: Double, state: MatchState, now: Date) -> Match {
        Match(id: "m\(minutesFromNow)_\(state.rawValue)", league: league, teamA: teamA, teamB: teamB,
              scoreA: 0, scoreB: 0,
              startTime: now.addingTimeInterval(minutesFromNow * 60), state: state)
    }
}

@Suite("TodayViewModel 폴링 주기")
struct TodayPollIntervalTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("라이브 경기가 있으면 가장 짧은 주기")
    func liveUsesShortest() {
        let interval = TodayViewModel.pollInterval(liveCount: 2, scheduled: [], now: now)
        #expect(interval == TodayViewModel.livePollInterval)
    }

    @Test("라이브도 없고 예정 경기도 없으면 가장 긴 주기")
    func idleUsesLongest() {
        let interval = TodayViewModel.pollInterval(liveCount: 0, scheduled: [], now: now)
        #expect(interval == TodayViewModel.idlePollInterval)
    }

    @Test("시작 시각이 지났는데 아직 unstarted면 짧은 주기로 시작을 기다린다")
    func overdueUsesShortest() {
        let overdue = PollFixture.match(minutesFromNow: -3, state: .unstarted, now: now)
        let interval = TodayViewModel.pollInterval(liveCount: 0, scheduled: [overdue], now: now)
        #expect(interval == TodayViewModel.livePollInterval)
    }

    @Test("30분 안에 시작할 경기가 있으면 중간 주기")
    func soonUsesMedium() {
        let soon = PollFixture.match(minutesFromNow: 20, state: .unstarted, now: now)
        let interval = TodayViewModel.pollInterval(liveCount: 0, scheduled: [soon], now: now)
        #expect(interval == TodayViewModel.upcomingPollInterval)
    }

    @Test("30분 경계 밖 경기만 있으면 긴 주기")
    func farAwayUsesLongest() {
        let far = PollFixture.match(minutesFromNow: 120, state: .unstarted, now: now)
        #expect(TodayViewModel.pollInterval(liveCount: 0, scheduled: [far], now: now)
                == TodayViewModel.idlePollInterval)
    }

    @Test("이미 완료된 경기는 주기 계산에 영향을 주지 않는다")
    func completedIsIgnored() {
        let done = PollFixture.match(minutesFromNow: -10, state: .completed, now: now)
        #expect(TodayViewModel.pollInterval(liveCount: 0, scheduled: [done], now: now)
                == TodayViewModel.idlePollInterval)
    }

    @Test("가장 급한 경기 기준으로 정해진다")
    func picksMostUrgent() {
        let far  = PollFixture.match(minutesFromNow: 300, state: .unstarted, now: now)
        let soon = PollFixture.match(minutesFromNow: 5,   state: .unstarted, now: now)
        #expect(TodayViewModel.pollInterval(liveCount: 0, scheduled: [far, soon], now: now)
                == TodayViewModel.upcomingPollInterval)
    }
}

@Suite("MatchDetailViewModel 폴링 주기")
struct MatchDetailPollIntervalTests {

    @Test("진행 중인 게임이 있으면 짧은 주기")
    func inProgressUsesShortest() {
        #expect(MatchDetailViewModel.pollInterval(hasLiveGame: true)
                == MatchDetailViewModel.livePollInterval)
    }

    @Test("아직 시작 안 한 경기는 긴 주기로 시작만 기다린다")
    func notStartedUsesLonger() {
        #expect(MatchDetailViewModel.pollInterval(hasLiveGame: false)
                == MatchDetailViewModel.waitingPollInterval)
    }
}
