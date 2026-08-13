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
/// 정리한 값(원본 필드명은 `OracleElixirService`에서 이걸로 변환됨).
/// 필드 의미는 oracleselixir.com 공개 자료 기준(EGR/MLR: Early/Mid-Late Game Rating,
/// GPR: Gold % Rating — 게임 전체 골드 점유율을 50 기준 편차로 표현, GSPD: Gold Spent % Diff).
struct TeamSeasonStats: Codable, Hashable {
    let games: Int
    let wins: Int
    let losses: Int
    let avgGameMinutes: Double
    let firstBloodRate: Double   // 0.0~1.0
    let dragonRate: Double       // 0.0~1.0 — 전체 드래곤 중 이 팀이 가져간 비율
    let baronRate: Double        // 0.0~1.0
    let goldDiffAt15: Double     // 분당이 아니라 15분 시점 골드 차이(음수 가능)

    // 상세 화면(TeamStatsDetailSheet)에서만 쓰는 확장 필드
    let kills: Int
    let deaths: Int
    let killDeathRatio: Double
    let combinedKillsPerMinute: Double   // CKPM
    let goldPercentRating: Double        // GPR, 50 기준 편차(+1.00 = 51%)
    let goldSpentPercentDiff: Double     // GSPD, 상대 대비 골드 소비 격차(비율)
    let earlyGameRating: Double          // EGR
    let midLateRating: Double            // MLR
    let firstTowerRate: Double           // FT%
    let firstToThreeTowersRate: Double   // F3T%
    let platesPerGame: Double            // PPG, 게임당 획득 타워 골드판 수
    let heraldRate: Double               // HLD%
    let voidGrubsRate: Double            // GRB%
    let firstDragonRate: Double          // FD%
    let elderDragonRate: Double?         // ELD%, 장로 드래곤 등장이 없던 시즌엔 nil
    let firstBaronRate: Double           // FBN%
    let laneCsShare: Double              // LNE%
    let jungleCsShare: Double            // JNG%
    let wardsPerMinute: Double           // WPM
    let controlWardsPerMinute: Double    // CWPM
    let wardsClearedPerMinute: Double    // WCPM

    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
}
