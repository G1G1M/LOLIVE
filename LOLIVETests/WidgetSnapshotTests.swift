//
//  WidgetSnapshotTests.swift
//  LOLIVETests
//
//  위젯 스냅샷 "내용이 실제로 바뀌었는지" 판정 테스트.
//  위젯 타임라인 리로드는 iOS가 하루 할당량을 두고 배분하므로 라이브 폴링마다 부르면 안 된다.
//  savedAt은 저장할 때마다 달라지는 메타데이터라 비교에서 빠져야 한다 — 이게 핵심.
//

import Testing
import Foundation
@testable import LOLIVE

private func entry(
    opponentCode: String = "T1",
    isLive: Bool = true,
    myScore: Int? = 1,
    oppScore: Int? = 0,
    currentGame: Int? = 2,
    startTime: Date = Date(timeIntervalSince1970: 1_800_000_000),
    savedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> SharedNextMatch {
    SharedNextMatch(
        opponentName: "Opponent", opponentCode: opponentCode, opponentImageURL: nil,
        startTime: startTime, isLive: isLive, leagueName: "LCK", savedAt: savedAt,
        myScore: myScore, oppScore: oppScore, currentGame: currentGame
    )
}

@Suite("위젯 스냅샷 변경 판정")
struct WidgetSnapshotTests {

    @Test("savedAt만 다르면 '안 바뀐 것'으로 본다")
    func savedAtIsIgnored() {
        let a = entry(savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let b = entry(savedAt: Date(timeIntervalSince1970: 1_800_009_999))
        #expect(a.hasSameDisplayContent(as: b))
    }

    @Test("스코어가 바뀌면 바뀐 것으로 본다")
    func scoreChangeIsDetected() {
        #expect(!entry(myScore: 1).hasSameDisplayContent(as: entry(myScore: 2)))
    }

    @Test("세트 번호가 바뀌면 바뀐 것으로 본다")
    func setChangeIsDetected() {
        #expect(!entry(currentGame: 2).hasSameDisplayContent(as: entry(currentGame: 3)))
    }

    @Test("라이브 여부가 바뀌면 바뀐 것으로 본다")
    func liveFlagChangeIsDetected() {
        #expect(!entry(isLive: true).hasSameDisplayContent(as: entry(isLive: false)))
    }

    @Test("시작 시각이 바뀌면 바뀐 것으로 본다")
    func startTimeChangeIsDetected() {
        let later = Date(timeIntervalSince1970: 1_800_003_600)
        #expect(!entry().hasSameDisplayContent(as: entry(startTime: later)))
    }

    @Test("맵 전체 비교 — savedAt만 다른 스냅샷은 같다고 본다")
    func mapComparisonIgnoresSavedAt() {
        let before = ["T1": entry(savedAt: Date(timeIntervalSince1970: 1)),
                      "GEN": entry(opponentCode: "GEN", savedAt: Date(timeIntervalSince1970: 1))]
        let after  = ["T1": entry(savedAt: Date(timeIntervalSince1970: 9999)),
                      "GEN": entry(opponentCode: "GEN", savedAt: Date(timeIntervalSince1970: 9999))]
        #expect(SharedNextMatch.sameDisplayContent(before, after))
    }

    @Test("팀이 추가되면 바뀐 것으로 본다")
    func addedTeamIsDetected() {
        let before = ["T1": entry()]
        let after  = ["T1": entry(), "GEN": entry(opponentCode: "GEN")]
        #expect(!SharedNextMatch.sameDisplayContent(before, after))
    }

    @Test("팀이 빠지면 바뀐 것으로 본다")
    func removedTeamIsDetected() {
        let before = ["T1": entry(), "GEN": entry(opponentCode: "GEN")]
        let after  = ["T1": entry()]
        #expect(!SharedNextMatch.sameDisplayContent(before, after))
    }

    @Test("같은 개수라도 키가 다르면 바뀐 것으로 본다")
    func differentKeysAreDetected() {
        #expect(!SharedNextMatch.sameDisplayContent(["T1": entry()],
                                                    ["GEN": entry(opponentCode: "GEN")]))
    }

    @Test("빈 스냅샷끼리는 같다")
    func emptyEqualsEmpty() {
        #expect(SharedNextMatch.sameDisplayContent([:], [:]))
    }
}
