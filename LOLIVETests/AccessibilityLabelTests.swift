//
//  AccessibilityLabelTests.swift
//  LOLIVETests
//
//  VoiceOver 라벨 문장 생성 테스트.
//  경기 카드는 팀명·상태·스코어가 각각 별개 요소라, 그대로 두면 "T1", "LIVE", "2", "3", "GEN"이
//  따로 읽혀서 어느 팀이 몇 점인지 알 수 없다. 한 문장으로 합치는 규칙을 고정한다.
//

import Testing
import Foundation
@testable import LOLIVE

private let lck = League(id: "L", slug: "lck", name: "LCK", region: "한국", imageURL: nil)
private let t1  = Team(id: "T1",  name: "T1",    code: "T1",  imageURL: nil)
private let gen = Team(id: "GEN", name: "Gen.G", code: "GEN", imageURL: nil)

private func match(scoreA: Int = 0, scoreB: Int = 0,
                   state: MatchState = .unstarted,
                   startTime: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> Match {
    Match(id: "m", league: lck, teamA: t1, teamB: gen,
          scoreA: scoreA, scoreB: scoreB, startTime: startTime, state: state)
}

@Suite("경기 카드 VoiceOver 라벨")
struct MatchCardAccessibilityTests {

    @Test("진행 중이면 상태와 스코어를 함께 읽는다")
    func liveIncludesScore() {
        let label = MatchCardView.accessibilityLabel(
            match: match(scoreA: 2, scoreB: 1, state: .inProgress), isEffectivelyLive: true, showDate: false)
        #expect(label.contains("T1"))
        #expect(label.contains("Gen.G"))
        #expect(label.contains("진행 중"))
        #expect(label.contains("2 대 1"))
    }

    @Test("종료된 경기는 '경기 종료'와 최종 스코어")
    func completedIncludesFinalScore() {
        let label = MatchCardView.accessibilityLabel(
            match: match(scoreA: 0, scoreB: 3, state: .completed), isEffectivelyLive: false, showDate: false)
        #expect(label.contains("경기 종료"))
        #expect(label.contains("0 대 3"))
    }

    @Test("시작 전 경기는 스코어 대신 예정 시각을 읽는다")
    func unstartedReadsScheduledTime() {
        let label = MatchCardView.accessibilityLabel(
            match: match(state: .unstarted), isEffectivelyLive: false, showDate: false)
        #expect(label.contains("예정"))
        #expect(!label.contains("대 0"))   // 0 대 0 을 읽어주면 안 된다
    }

    @Test("getLive 목록에 없어도 inProgress면 진행 중으로 읽는다")
    func inProgressWithoutLiveFlag() {
        let label = MatchCardView.accessibilityLabel(
            match: match(scoreA: 1, scoreB: 0, state: .inProgress), isEffectivelyLive: true, showDate: false)
        #expect(label.contains("진행 중"))
    }

    @Test("날짜 표시 모드면 날짜도 포함한다")
    func showDateIncludesDate() {
        let withDate = MatchCardView.accessibilityLabel(
            match: match(state: .completed, startTime: Date(timeIntervalSince1970: 1_800_000_000)),
            isEffectivelyLive: false, showDate: true)
        let without = MatchCardView.accessibilityLabel(
            match: match(state: .completed), isEffectivelyLive: false, showDate: false)
        #expect(withDate.count > without.count)
    }

    @Test("팀 이름이 비어 있으면 코드로 읽는다")
    func fallsBackToTeamCode() {
        let noName = Team(id: "X", name: "", code: "XYZ", imageURL: nil)
        let m = Match(id: "m", league: lck, teamA: noName, teamB: gen,
                      scoreA: 1, scoreB: 0, startTime: Date(), state: .completed)
        #expect(MatchCardView.accessibilityLabel(match: m, isEffectivelyLive: false, showDate: false)
                .contains("XYZ"))
    }
}

@Suite("포지션 배지 VoiceOver 라벨")
struct RoleAccessibilityTests {

    @Test("약어 대신 한글 포지션 이름을 읽는다")
    func readsKoreanRoleName() {
        #expect(RoleStyle.accessibilityLabel("top") == "탑")
        #expect(RoleStyle.accessibilityLabel("jungle") == "정글")
        #expect(RoleStyle.accessibilityLabel("mid") == "미드")
        #expect(RoleStyle.accessibilityLabel("support") == "서포터")
    }

    @Test("bottom과 bot 둘 다 같은 이름")
    func bottomAliases() {
        #expect(RoleStyle.accessibilityLabel("bottom") == RoleStyle.accessibilityLabel("bot"))
    }

    @Test("모르는 포지션은 원본을 그대로 읽는다")
    func unknownRoleFallsBack() {
        #expect(RoleStyle.accessibilityLabel("coach") == "coach")
    }
}
