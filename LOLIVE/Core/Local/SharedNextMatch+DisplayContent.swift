//
//  SharedNextMatch+DisplayContent.swift
//  LOLIVE
//
//  위젯 스냅샷의 "내용이 실제로 바뀌었는지" 판정.
//
//  SharedDataService.swift 본체가 아니라 별도 파일에 두는 이유: 그 파일은 위젯 타겟과
//  물리적으로 복제돼 있어서, 앱에서만 쓰는 코드를 넣으면 두 사본이 어긋난다.
//

import Foundation

extension SharedNextMatch {

    /// 위젯 화면에 실제로 나타나는 값들이 같은지.
    ///
    /// `savedAt`은 일부러 뺀다 — 저장할 때마다 `Date()`로 새로 찍히는 메타데이터(위젯이 스냅샷
    /// 신선도를 판정하는 용도)라, 포함하면 "바뀌었나?"가 항상 참이 되어 판정 자체가 무의미해진다.
    func hasSameDisplayContent(as other: SharedNextMatch) -> Bool {
        opponentName == other.opponentName &&
        opponentCode == other.opponentCode &&
        opponentImageURL == other.opponentImageURL &&
        startTime == other.startTime &&
        isLive == other.isLive &&
        leagueName == other.leagueName &&
        myScore == other.myScore &&
        oppScore == other.oppScore &&
        currentGame == other.currentGame
    }

    /// 팀코드 → 스냅샷 맵 두 개가 화면에 보이는 내용 기준으로 같은지.
    static func sameDisplayContent(_ lhs: [String: SharedNextMatch],
                                   _ rhs: [String: SharedNextMatch]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (teamCode, entry) in lhs {
            guard let counterpart = rhs[teamCode],
                  entry.hasSameDisplayContent(as: counterpart)
            else { return false }
        }
        return true
    }
}
