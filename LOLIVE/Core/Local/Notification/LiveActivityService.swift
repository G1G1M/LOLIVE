//
//  LiveActivityService.swift
//  LOLIVE

import ActivityKit
import Foundation
import UIKit
import os

@MainActor
final class LiveActivityService {

    static let shared = LiveActivityService()
    var activities: [String: Activity<MatchActivityAttributes>] = [:]
    let logger = Logger(subsystem: "com.lolive", category: "LiveActivity")

    private init() {
        // 앱 재시작 시 ActivityKit에 살아있는 기존 Activity를 딕셔너리에 복원
        // → 없으면 동일 경기에 대해 Activity가 중복 생성됨
        for activity in Activity<MatchActivityAttributes>.activities {
            activities[activity.attributes.matchId] = activity
        }
    }


    // MARK: - Public

    /// 잠금화면에 "경기종료"를 보여준 뒤 자동으로 사라질 때까지의 유예 시간.
    private static let finishedDismissDelay: TimeInterval = 15 * 60

    /// 폴링 결과로 liveMatches가 갱신될 때마다 호출
    /// — 즐겨찾기 팀의 경기 Live Activity를 시작/업데이트/종료
    /// - overdueMatches: startTime 지났으나 API 미확인 경기 (예약 시각부터 pre-live Activity 표시)
    /// - justCompletedMatches: 직전 폴링까지 라이브였다가 이번 폴링에서 사라진 경기(=방금 끝난 경기).
    ///   즐겨찾기 팀이 아니거나 Activity가 없던 경기가 섞여 있어도 안전 — 실제로 존재하는 Activity만 처리한다.
    func syncActivities(_ liveMatches: [LiveMatch], overdueMatches: [Match] = [], justCompletedMatches: [Match] = [], favoritedTeams: Set<FavoritedTeamRef>) async {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            #if DEBUG
            logger.debug("⚠️ [LiveActivity] 비활성화됨 — 설정 > LOLIVE > 실시간 활동에서 켜주세요")
            #endif
            return
        }

        // 방금 끝난 경기 → 즉시 지우지 않고 "경기종료" 최종 스코어로 한 번 갱신한 뒤
        // 유예 시간 후 자동으로 사라지게 한다. 여기서 처리한 id는 activities에서 바로 빼서
        // 아래 keepIds 정리 루프가 중복으로 건드리지 않게 한다.
        for match in justCompletedMatches {
            guard let activity = activities[match.id] else { continue }
            let attrs = activity.attributes
            let sameOrder = attrs.teamACode == match.teamA.code
            let finalScoreA = sameOrder ? match.scoreA : match.scoreB
            let finalScoreB = sameOrder ? match.scoreB : match.scoreA
            let state = MatchActivityAttributes.ContentState(
                scoreA: finalScoreA,
                scoreB: finalScoreB,
                currentGame: activity.content.state.currentGame,
                isLive: false,
                isFinished: true
            )
            await activity.end(.init(state: state, staleDate: nil),
                                dismissalPolicy: .after(Date().addingTimeInterval(Self.finishedDismissDelay)))
            activities.removeValue(forKey: match.id)
            #if DEBUG
            logger.debug("🏁 [LiveActivity] 경기종료 표시: \(attrs.teamACode) \(finalScoreA)-\(finalScoreB) \(attrs.teamBCode)")
            #endif
        }

        let relevant = liveMatches.filter {
            FavoritedTeamRef.matches(favoritedTeams, team: $0.match.teamA, league: $0.match.league) ||
            FavoritedTeamRef.matches(favoritedTeams, team: $0.match.teamB, league: $0.match.league)
        }

        // 라이브 경기 + 예약 시각 지난 경기 모두 유지 (둘 다 아닌 경우에만 종료)
        let liveIds = Set(relevant.map { $0.match.id })
        let overdueIds = Set(overdueMatches.map { $0.id })
        let keepIds = liveIds.union(overdueIds)
        for (id, activity) in activities where !keepIds.contains(id) {
            await activity.end(dismissalPolicy: .immediate)
            activities.removeValue(forKey: id)
        }

        // 진행 중인 경기 시작 또는 업데이트
        for liveMatch in relevant {
            if let activity = activities[liveMatch.match.id] {
                // attributes(teamA/teamB)는 Activity 생성 시 한 번 고정되고 이후 절대 못 바꾼다.
                // 반면 스코어는 매 폴링마다 새로 받아온 Match에서 다시 읽는데, Riot API가 팀 배열
                // 순서를 항상 같게 보장하지 않아서 그대로 넣으면 팀 라벨은 그대로인데 스코어만
                // 반대로 들어갈 수 있다 — 매번 코드로 순서를 대조해 필요하면 교차 배정한다.
                let attrs = activity.attributes
                let sameOrder = attrs.teamACode == liveMatch.match.teamA.code
                let scoreA = sameOrder ? liveMatch.match.scoreA : liveMatch.match.scoreB
                let scoreB = sameOrder ? liveMatch.match.scoreB : liveMatch.match.scoreA

                let state = MatchActivityAttributes.ContentState(
                    scoreA: scoreA,
                    scoreB: scoreB,
                    currentGame: liveMatch.currentSet,
                    isLive: true
                )

                // 세트가 바뀐 경우에만 다이나믹 아일랜드/잠금화면에 배너+알림음 표시
                // (매 폴링마다 조용히 갱신되는 것과 구분 — 세트 종료라는 의미 있는 순간에만 알림)
                let alert: AlertConfiguration? = activity.content.state.currentGame != state.currentGame
                    ? AlertConfiguration(
                        title: LocalizedStringResource(stringLiteral: "Game \(state.currentGame) 시작"),
                        body: LocalizedStringResource(stringLiteral: "\(attrs.teamACode) \(state.scoreA) - \(state.scoreB) \(attrs.teamBCode)"),
                        sound: .default
                      )
                    : nil
                await activity.update(.init(state: state, staleDate: nil), alertConfiguration: alert)
            } else {
                let state = MatchActivityAttributes.ContentState(
                    scoreA: liveMatch.match.scoreA,
                    scoreB: liveMatch.match.scoreB,
                    currentGame: liveMatch.currentSet,
                    isLive: true
                )

                // 두 팀 썸네일을 병렬로 fetch
                async let thumbA = fetchThumbnail(urlString: liveMatch.match.teamA.imageURL, teamCode: liveMatch.match.teamA.code)
                async let thumbB = fetchThumbnail(urlString: liveMatch.match.teamB.imageURL, teamCode: liveMatch.match.teamB.code)
                let (teamAImageData, teamBImageData) = await (thumbA, thumbB)

                // teamAImageURL/teamBImageURL은 attributes에 담지 않는다 (4KB 예산 절약) —
                // 위젯은 어차피 App Group 고화질 파일 → 썸네일 데이터 순으로 우선 사용하고,
                // URL은 그 둘 다 없을 때만 쓰는 최후 폴백이라 생략해도 실사용에 영향 없다.
                let attrs = MatchActivityAttributes(
                    matchId: liveMatch.match.id,
                    teamAName: liveMatch.match.teamA.name,
                    teamACode: liveMatch.match.teamA.code,
                    teamAImageURL: nil,
                    teamAImageData: teamAImageData,
                    teamBName: liveMatch.match.teamB.name,
                    teamBCode: liveMatch.match.teamB.code,
                    teamBImageURL: nil,
                    teamBImageData: teamBImageData,
                    leagueName: liveMatch.match.league.name,
                    blockName: liveMatch.match.blockName
                )
                do {
                    let activity = try Activity.request(
                        attributes: attrs,
                        content: .init(state: state, staleDate: nil),
                        pushType: nil
                    )
                    activities[liveMatch.match.id] = activity
                    #if DEBUG
                    logger.debug("✅ [LiveActivity] 시작: \(liveMatch.match.teamA.code) vs \(liveMatch.match.teamB.code) id=\(activity.id)")
                    logger.debug("   imgA=\(teamAImageData?.count ?? 0)B  imgB=\(teamBImageData?.count ?? 0)B")
                    #endif
                } catch {
                    #if DEBUG
                    logger.debug("❌ [LiveActivity] request 실패: \(error)")
                    #endif
                }
            }
        }

        // 예약 시각이 지났으나 API 미확인 경기 → pre-live Activity (isLive: false)
        for match in overdueMatches {
            guard activities[match.id] == nil else { continue }  // 이미 시작됨

            let state = MatchActivityAttributes.ContentState(
                scoreA: 0, scoreB: 0, currentGame: 1, isLive: false
            )
            async let thumbA = fetchThumbnail(urlString: match.teamA.imageURL, teamCode: match.teamA.code)
            async let thumbB = fetchThumbnail(urlString: match.teamB.imageURL, teamCode: match.teamB.code)
            let (teamAData, teamBData) = await (thumbA, thumbB)

            let attrs = MatchActivityAttributes(
                matchId: match.id,
                teamAName: match.teamA.name,
                teamACode: match.teamA.code,
                teamAImageURL: nil,
                teamAImageData: teamAData,
                teamBName: match.teamB.name,
                teamBCode: match.teamB.code,
                teamBImageURL: nil,
                teamBImageData: teamBData,
                leagueName: match.league.name,
                blockName: match.blockName
            )
            do {
                let activity = try Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                activities[match.id] = activity
                #if DEBUG
                logger.debug("⏰ [LiveActivity] 예약시작: \(match.teamA.code) vs \(match.teamB.code) id=\(activity.id)")
                #endif
            } catch {
                #if DEBUG
                logger.debug("❌ [LiveActivity] 예약시작 실패: \(error)")
                #endif
            }
        }
    }
}
