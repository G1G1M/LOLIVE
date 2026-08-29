//
//  LiveMatch.swift
//  LOLIVE
//

import Foundation

/// 지금 진행 중인 경기 하나.
///
/// **매번 달라지는 값(예: 조회 시각)을 여기 넣지 말 것.** 이 타입의 동일성이 곧
/// "폴링 결과가 실제로 달라졌는가"의 판정 기준이고, `TodayViewModel.liveMatches` 대입 여부가
/// 거기에 걸려 있다. 예전엔 `lastUpdated: Date`가 있었는데 정작 읽는 곳은 하나도 없으면서
/// 폴링마다 값이 달라져서, 내용이 그대로여도 Today 화면 전체가 매번 다시 그려지고
/// 위젯 타임라인 리로드까지 매번 요청되고 있었다.
struct LiveMatch: Codable, Identifiable, Hashable {
    var id: String { match.id }
    let match: Match
    let currentSet: Int
    /// 현재 진행 중인 게임(세트)의 esports game ID — 라이브 스탯 피드(feed.lolesports.com) 조회용
    let currentGameId: String?
}
