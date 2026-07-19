//
//  LeaguepediaCargo.swift
//  LOLIVE
//
//  Leaguepedia MediaWiki Cargo API 응답 모델과 내부 공유 타입 정의.
//  LeaguepediaService의 여러 Extension에서 공통으로 사용된다.
//

import Foundation

// MARK: - Cargo API 응답 모델

/// Leaguepedia Cargo API의 최상위 응답 구조체.
/// 모든 cargoquery 요청의 결과가 이 형태로 반환된다.
struct CargoResp: Decodable {
    let cargoquery: [CargoRow]
}

/// Cargo API의 단일 행(row).
/// `title` 딕셔너리 안에 컬럼 이름 → 값이 담겨 있다.
/// 값이 String/Number/Bool 혼합이므로 FlexValue로 통일 처리.
struct CargoRow: Decodable {
    let title: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: FlexValue].self, forKey: .title)
        title = raw.mapValues { $0.stringValue }
    }

    enum CodingKeys: String, CodingKey { case title }

    /// Cargo API 값이 String · Number · Bool 혼합으로 내려오는 문제 해결.
    /// 모두 String으로 통일해서 title 딕셔너리에 저장한다.
    private struct FlexValue: Decodable {
        let stringValue: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { stringValue = s; return }
            if let n = try? c.decode(Double.self) {
                stringValue = n.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(n)) : String(n)
                return
            }
            if let b = try? c.decode(Bool.self) { stringValue = b ? "1" : "0"; return }
            stringValue = ""
        }
    }
}

// MARK: - 내부 공유 타입

/// Leaguepedia MatchSchedule 테이블에서 가져온 대회 페이지 정보.
/// - `page`: Leaguepedia OverviewPage 이름 (예: "LCK/2025 Season/Spring Split")
/// - `year`: DateStart 기준 연도 (연도 탭 생성에 사용)
struct LPTournamentEntry: Codable {
    let page: String
    let year: Int
}

/// Leaguepedia ScoreboardGames에서 가져온 밴 정보.
/// AppDiskCache에 직렬화해 30일 캐싱한다.
struct BansCacheEntry: Codable {
    let team1Bans: [String]
    let team2Bans: [String]
}
