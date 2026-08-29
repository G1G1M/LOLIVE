//
//  LiveMatchIdentityTests.swift
//  LOLIVETests
//
//  LiveMatch 동일성이 "내용" 기준인지 고정한다.
//
//  [왜 중요한가] TodayViewModel.liveMatches 는 @Observable 프로퍼티라, 값을 대입하는 순간
//  이걸 읽는 모든 뷰가 무효화된다. 폴링은 30초마다 도는데 대부분의 폴링은 직전과 완전히 같은
//  결과를 받는다 — 그래서 폴링 루프는 "내용이 달라졌을 때만" 대입한다.
//  LiveMatch 에 저장 시각 같은 매번 달라지는 필드가 다시 들어오면 이 비교가 항상 false 가 되어
//  그 최적화가 통째로 무력화된다(실제로 lastUpdated 필드가 그랬다).
//

import Testing
import Foundation
@testable import LOLIVE

private let league = League(id: "L", slug: "lck", name: "LCK", region: "한국", imageURL: nil)
private let t1  = Team(id: "T1",  name: "T1",    code: "T1",  imageURL: nil)
private let gen = Team(id: "GEN", name: "Gen.G", code: "GEN", imageURL: nil)
private let kickoff = Date(timeIntervalSince1970: 1_800_000_000)

private func live(scoreA: Int = 1, scoreB: Int = 0, currentSet: Int = 2,
                  gameId: String? = "g1") -> LiveMatch {
    LiveMatch(
        match: Match(id: "m1", league: league, teamA: t1, teamB: gen,
                     scoreA: scoreA, scoreB: scoreB, startTime: kickoff, state: .inProgress),
        currentSet: currentSet,
        currentGameId: gameId
    )
}

@Suite("LiveMatch 동일성")
struct LiveMatchIdentityTests {

    @Test("같은 내용이면 두 번 만들어도 같다")
    func sameContentIsEqual() {
        #expect(live() == live())
    }

    @Test("같은 내용의 배열도 같다 — 폴링 결과 비교가 여기에 걸린다")
    func sameArrayIsEqual() {
        #expect([live()] == [live()])
    }

    @Test("스코어가 바뀌면 다르다")
    func scoreChangeIsDetected() {
        #expect(live(scoreA: 1) != live(scoreA: 2))
    }

    @Test("세트 번호가 바뀌면 다르다")
    func setChangeIsDetected() {
        #expect(live(currentSet: 2) != live(currentSet: 3))
    }

    @Test("진행 중인 게임 id가 바뀌면 다르다")
    func gameIdChangeIsDetected() {
        #expect(live(gameId: "g1") != live(gameId: "g2"))
    }
}
