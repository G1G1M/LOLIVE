//
//  Team.swift
//  LOLIVE
//

import Foundation

struct Team: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let code: String
    let imageURL: String?
}

/// 팀 단위 시즌 집계 스탯 — Oracle's Elixir `/stats/teams/byTournament` 응답을 앱에서 쓰기 좋게
/// 정리한 값(원본 필드명 AGT/FB%/DRG%/BN%/GD15는 `OracleElixirService`에서 이걸로 변환됨).
struct TeamSeasonStats: Codable, Hashable {
    let games: Int
    let wins: Int
    let losses: Int
    let avgGameMinutes: Double
    let firstBloodRate: Double   // 0.0~1.0
    let dragonRate: Double       // 0.0~1.0 — 전체 드래곤 중 이 팀이 가져간 비율
    let baronRate: Double        // 0.0~1.0
    let goldDiffAt15: Double     // 분당이 아니라 15분 시점 골드 차이(음수 가능)

    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
}
