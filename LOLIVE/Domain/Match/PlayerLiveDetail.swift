//
//  PlayerLiveDetail.swift
//  LOLIVE
//
//  `feed.lolesports.com/livestats/v1/details/{gameId}` 가 주는 선수별 상세.
//  같은 피드의 `window`가 스코어보드 수준(골드·KDA·CS)이라면, 이쪽은 그 선수가
//  "어떻게 하고 있는지"에 해당한다 — 아이템 빌드, 룬, 스킬 마스터 순서,
//  킬 관여율·딜 비중, 시야 장악, 현재 전투 스탯.
//
//  [주의] 이 응답에는 `events`와 `gameTime` 필드가 없다(2026-08-27 실측).
//  예전엔 있었던 것으로 보이며, 킬 타임라인과 인게임 시계가 여기 의존하다가
//  조용히 빈 값을 반환하고 있었다. 다시 생기더라도 테스트로 먼저 확인할 것.
//

import Foundation

struct PlayerLiveDetail: Identifiable, Codable, Hashable {
    var id: Int { participantId }

    let participantId: Int
    let level: Int
    let kills: Int
    let deaths: Int
    let assists: Int
    let totalGoldEarned: Int
    let creepScore: Int

    // MARK: 기여도 (0.0 ~ 1.0)

    /// 팀 킬 중 이 선수가 관여(킬 또는 어시스트)한 비율.
    let killParticipation: Double
    /// 팀 전체 챔피언 대상 피해량 중 이 선수의 비중.
    let championDamageShare: Double

    // MARK: 시야

    let wardsPlaced: Int
    let wardsDestroyed: Int

    // MARK: 현재 전투 스탯 (아이템을 살 때마다 바뀐다)

    let attackDamage: Int
    let abilityPower: Int
    let armor: Int
    let magicResistance: Int
    let attackSpeed: Int
    /// 비율 필드는 정수로 올 때가 많지만(`0`) 소수도 오므로 Double로 받는다.
    let criticalChance: Double
    let lifeSteal: Double
    let tenacity: Double

    // MARK: 빌드

    /// 인벤토리 아이템 ID. DDragon `item.json` 으로 이름·아이콘을 찾는다.
    let items: [Int]
    /// 메인 룬 계열 ID (예: 8400 = 결의).
    let perkStyleId: Int?
    /// 서브 룬 계열 ID.
    let perkSubStyleId: Int?
    /// 선택한 룬 ID 목록.
    let perks: [Int]
    /// 레벨업 순서대로 찍은 스킬(예: `["Q","W","E","Q",...]`).
    let abilities: [String]

    var kda: String { "\(kills)/\(deaths)/\(assists)" }
}

/// 한 게임의 특정 시점 상세 스냅샷. 완료 경기는 더 이상 안 변해서 캐싱해도 안전하다.
struct GameLiveDetail: Codable, Hashable {
    let gameId: String
    let capturedAt: Date?
    let players: [PlayerLiveDetail]

    func player(_ participantId: Int) -> PlayerLiveDetail? {
        players.first { $0.participantId == participantId }
    }
}
