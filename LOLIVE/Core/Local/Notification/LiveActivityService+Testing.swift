//
//  LiveActivityService+Testing.swift
//  LOLIVE
//
//  실제 경기 없이 Dynamic Island / 잠금화면 표시를 확인하기 위한 더미 Activity.
//  DEBUG 빌드에서만 컴파일되며, 앱 설정 화면의 테스트 버튼이 호출한다.
//

#if DEBUG
import ActivityKit
import Foundation
import os

extension LiveActivityService {

    /// 테스트용 더미 경기 ID — 실제 경기 Activity와 충돌하지 않는 고정 값
    private static let testMatchId = "lolive_test_activity"

    /// 테스트 Activity가 실행 중인지 여부 (설정 화면 버튼 상태용)
    var isTestActivityRunning: Bool {
        activities[Self.testMatchId] != nil
    }

    /// 더미 경기(T1 vs Gen.G)로 Live Activity 즉시 시작.
    /// 실제 경기 시간과 무관하게 Dynamic Island / 잠금화면 표시를 확인할 수 있다.
    /// - Returns: 시작 성공 여부 (실패 시 설정 > 실시간 활동 비활성화가 원인일 가능성)
    @discardableResult
    func startTestActivity() async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.debug("⚠️ [LiveActivity 테스트] 비활성화됨 — 설정 > LOLIVE > 실시간 활동 확인")
            return false
        }
        guard activities[Self.testMatchId] == nil else { return true }  // 이미 실행 중

        // 실제 로고를 fetch해 위젯 이미지 표시까지 함께 검증
        async let thumbA = fetchThumbnail(
            urlString: "https://lol.fandom.com/wiki/Special:FilePath/T1logo_std.png",
            teamCode: "T1")
        async let thumbB = fetchThumbnail(
            urlString: "https://lol.fandom.com/wiki/Special:FilePath/Gen.Glogo_std.png",
            teamCode: "GEN")
        let (teamAData, teamBData) = await (thumbA, thumbB)

        let attrs = MatchActivityAttributes(
            matchId: Self.testMatchId,
            teamAName: "T1",
            teamACode: "T1",
            teamAImageURL: nil,
            teamAImageData: teamAData,
            teamBName: "Gen.G",
            teamBCode: "GEN",
            teamBImageURL: nil,
            teamBImageData: teamBData,
            leagueName: "LCK (테스트)",
            blockName: "3주 차"
        )
        let state = MatchActivityAttributes.ContentState(
            scoreA: 0, scoreB: 0, currentGame: 1, isLive: true
        )
        do {
            let activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            activities[Self.testMatchId] = activity
            logger.debug("✅ [LiveActivity 테스트] 시작 id=\(activity.id)")
            return true
        } catch {
            logger.debug("❌ [LiveActivity 테스트] 시작 실패: \(error)")
            return false
        }
    }

    /// 테스트 Activity의 스코어/세트 업데이트 — 실시간 갱신 동작 검증용.
    /// 세트 번호가 바뀌면 실제 syncActivities와 동일하게 배너+알림음을 함께 트리거한다.
    func updateTestActivity(scoreA: Int, scoreB: Int, currentGame: Int) async {
        guard let activity = activities[Self.testMatchId] else { return }
        let alert: AlertConfiguration? = activity.content.state.currentGame != currentGame
            ? AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: "Game \(currentGame) 시작"),
                body: LocalizedStringResource(stringLiteral: "T1 \(scoreA) - \(scoreB) GEN"),
                sound: .default
              )
            : nil
        let state = MatchActivityAttributes.ContentState(
            scoreA: scoreA, scoreB: scoreB, currentGame: currentGame, isLive: true
        )
        await activity.update(.init(state: state, staleDate: nil), alertConfiguration: alert)
        logger.debug("🔄 [LiveActivity 테스트] 업데이트 \(scoreA):\(scoreB) 세트\(currentGame)")
    }

    /// 테스트 Activity 즉시 종료.
    func endTestActivity() async {
        guard let activity = activities[Self.testMatchId] else { return }
        await activity.end(dismissalPolicy: .immediate)
        activities.removeValue(forKey: Self.testMatchId)
        logger.debug("🏁 [LiveActivity 테스트] 종료")
    }
}
#endif
