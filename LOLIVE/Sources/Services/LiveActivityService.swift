//
//  LiveActivityService.swift
//  LOLIVE
//

import ActivityKit
import Foundation

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

    private func fetchImageData(_ urlString: String?) async -> Data? {
        guard let str = urlString, let url = URL(string: str) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    // MARK: - Public

    /// 폴링 결과로 liveMatches가 갱신될 때마다 호출
    /// — 즐겨찾기 팀의 경기 Live Activity를 시작/업데이트/종료
    func syncActivities(_ liveMatches: [LiveMatch], favoritedTeamIds: Set<String>) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let relevant = liveMatches.filter {
            favoritedTeamIds.contains($0.match.teamA.id) ||
            favoritedTeamIds.contains($0.match.teamB.id) ||
            favoritedTeamIds.contains($0.match.teamA.code) ||
            favoritedTeamIds.contains($0.match.teamB.code)
        }

        // 더 이상 진행 중이지 않은 경기 종료
        let liveIds = Set(relevant.map { $0.match.id })
        for (id, activity) in activities where !liveIds.contains(id) {
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
                await activity.update(.init(state: state, staleDate: nil))
            } else {
                // Live Activity 시작 전 팀 로고를 App Group에 캐시 (Live Activity는 AsyncImage 불가)
                async let imgATask = fetchImageData(liveMatch.match.teamA.imageURL)
                async let imgBTask = fetchImageData(liveMatch.match.teamB.imageURL)
                let (imgA, imgB) = await (imgATask, imgBTask)
                if let imgA { SharedDataService.saveTeamImageData(imgA, teamCode: liveMatch.match.teamA.code) }
                if let imgB { SharedDataService.saveTeamImageData(imgB, teamCode: liveMatch.match.teamB.code) }

                let attrs = MatchActivityAttributes(
                    matchId: liveMatch.match.id,
                    teamAName: liveMatch.match.teamA.name,
                    teamACode: liveMatch.match.teamA.code,
                    teamAImageURL: liveMatch.match.teamA.imageURL,
                    teamBName: liveMatch.match.teamB.name,
                    teamBCode: liveMatch.match.teamB.code,
                    teamBImageURL: liveMatch.match.teamB.imageURL,
                    leagueName: liveMatch.match.league.name
                )
                let activity = try? Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil)
                )
                if let activity {
                    activities[liveMatch.match.id] = activity
                }
            }
        }
    }
}
