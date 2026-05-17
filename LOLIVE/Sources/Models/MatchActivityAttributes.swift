//
//  MatchActivityAttributes.swift
//  LOLIVE
//
//  ⚠️ 이 파일은 메인 앱 타겟(LOLIVE)과 Widget Extension 타겟(LOLIVEWidgets)
//     양쪽 모두에 추가해야 합니다.
//

import ActivityKit
import Foundation

struct MatchActivityAttributes: ActivityAttributes {

    // 경기 진행 중 실시간 변경되는 데이터
    struct ContentState: Codable, Hashable {
        var scoreA: Int
        var scoreB: Int
        var currentGame: Int
        var isLive: Bool
    }

    // 경기 시작 시 고정되는 정적 데이터
    let matchId: String
    let teamAName: String
    let teamACode: String
    let teamAImageURL: String?
    let teamBName: String
    let teamBCode: String
    let teamBImageURL: String?
    let leagueName: String
}
