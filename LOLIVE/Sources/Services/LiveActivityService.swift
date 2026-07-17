//
//  LiveActivityService.swift
//  LOLIVE

import ActivityKit
import Foundation
import UIKit

@MainActor
final class LiveActivityService {

    static let shared = LiveActivityService()
    private var activities: [String: Activity<MatchActivityAttributes>] = [:]

    private init() {
        // 앱 재시작 시 ActivityKit에 살아있는 기존 Activity를 딕셔너리에 복원
        // → 없으면 동일 경기에 대해 Activity가 중복 생성됨
        for activity in Activity<MatchActivityAttributes>.activities {
            activities[activity.attributes.matchId] = activity
        }
    }

    // MARK: - Private

    /// URL에서 이미지를 fetch해 30×30 PNG 썸네일로 변환 후 반환.
    /// 반환된 Data는 MatchActivityAttributes에 직접 포함되어 ActivityKit이 위젯 Extension에 전달.
    private func fetchThumbnail(urlString: String?, teamCode: String) async -> Data? {
        guard let str = urlString, let url = URL(string: str) else {
            print("🖼️ [\(teamCode)] URL 없음")
            return nil
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            print("🖼️ [\(teamCode)] 네트워크 fetch 실패")
            return nil
        }
        guard let original = UIImage(data: data) else {
            print("🖼️ [\(teamCode)] UIImage 변환 실패")
            return nil
        }
        // 30×30으로 리사이즈해 PNG 크기를 최소화
        let size = CGSize(width: 30, height: 30)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { _ in
            original.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = thumbnail.pngData() else {
            print("🖼️ [\(teamCode)] PNG 변환 실패")
            return nil
        }
        print("🖼️ [\(teamCode)] ✅ 썸네일 준비: \(png.count) bytes (30×30 PNG)")
        return png
    }

    // MARK: - Public

    /// 폴링 결과로 liveMatches가 갱신될 때마다 호출
    /// — 즐겨찾기 팀의 경기 Live Activity를 시작/업데이트/종료
    /// - overdueMatches: startTime 지났으나 API 미확인 경기 (예약 시각부터 pre-live Activity 표시)
    func syncActivities(_ liveMatches: [LiveMatch], overdueMatches: [Match] = [], favoritedTeamIds: Set<String>) async {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            #if DEBUG
            print("⚠️ [LiveActivity] 비활성화됨 — 설정 > LOLIVE > 실시간 활동에서 켜주세요")
            #endif
            return
        }

        let relevant = liveMatches.filter {
            favoritedTeamIds.contains($0.match.teamA.id) ||
            favoritedTeamIds.contains($0.match.teamB.id) ||
            favoritedTeamIds.contains($0.match.teamA.code) ||
            favoritedTeamIds.contains($0.match.teamB.code)
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
            let state = MatchActivityAttributes.ContentState(
                scoreA: liveMatch.match.scoreA,
                scoreB: liveMatch.match.scoreB,
                currentGame: liveMatch.currentSet,
                isLive: true
            )

            if let activity = activities[liveMatch.match.id] {
                // 기존 Activity 업데이트
                await activity.update(.init(state: state, staleDate: nil))
            } else {
                // 두 팀 썸네일을 병렬로 fetch
                async let thumbA = fetchThumbnail(urlString: liveMatch.match.teamA.imageURL, teamCode: liveMatch.match.teamA.code)
                async let thumbB = fetchThumbnail(urlString: liveMatch.match.teamB.imageURL, teamCode: liveMatch.match.teamB.code)
                let (teamAImageData, teamBImageData) = await (thumbA, thumbB)

                let attrs = MatchActivityAttributes(
                    matchId: liveMatch.match.id,
                    teamAName: liveMatch.match.teamA.name,
                    teamACode: liveMatch.match.teamA.code,
                    teamAImageURL: liveMatch.match.teamA.imageURL,
                    teamAImageData: teamAImageData,
                    teamBName: liveMatch.match.teamB.name,
                    teamBCode: liveMatch.match.teamB.code,
                    teamBImageURL: liveMatch.match.teamB.imageURL,
                    teamBImageData: teamBImageData,
                    leagueName: liveMatch.match.league.name
                )
                do {
                    let activity = try Activity.request(
                        attributes: attrs,
                        content: .init(state: state, staleDate: nil),
                        pushType: nil
                    )
                    activities[liveMatch.match.id] = activity
                    #if DEBUG
                    print("✅ [LiveActivity] 시작: \(liveMatch.match.teamA.code) vs \(liveMatch.match.teamB.code) id=\(activity.id)")
                    print("   imgA=\(teamAImageData?.count ?? 0)B  imgB=\(teamBImageData?.count ?? 0)B")
                    #endif
                } catch {
                    #if DEBUG
                    print("❌ [LiveActivity] request 실패: \(error)")
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
                teamAImageURL: match.teamA.imageURL,
                teamAImageData: teamAData,
                teamBName: match.teamB.name,
                teamBCode: match.teamB.code,
                teamBImageURL: match.teamB.imageURL,
                teamBImageData: teamBData,
                leagueName: match.league.name
            )
            do {
                let activity = try Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                activities[match.id] = activity
                #if DEBUG
                print("⏰ [LiveActivity] 예약시작: \(match.teamA.code) vs \(match.teamB.code) id=\(activity.id)")
                #endif
            } catch {
                #if DEBUG
                print("❌ [LiveActivity] 예약시작 실패: \(error)")
                #endif
            }
        }
    }
}
