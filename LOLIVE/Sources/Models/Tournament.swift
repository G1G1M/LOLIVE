//
//  Tournament.swift
//  LOLIVE
//

import Foundation

struct Tournament: Codable, Identifiable {
    let id: String
    let slug: String
    let startDate: String   // "2025-01-15" 형식
    let endDate: String
}

// MARK: - Shared Utility

/// 토너먼트 목록에서 현재 진행 중인 가장 적합한 토너먼트를 반환.
/// 1순위: 진행 중인 정규시즌 / 2순위: 진행 중인 플레이오프 / 3순위: 가장 최근 완료된 정규시즌 / 4순위: 가장 최근 토너먼트
func activeTournament(from tournaments: [Tournament]) -> Tournament? {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let now = Date()
    let sorted = tournaments.sorted {
        (fmt.date(from: $0.startDate) ?? .distantPast) >
        (fmt.date(from: $1.startDate) ?? .distantPast)
    }
    func isSpecial(_ t: Tournament) -> Bool {
        let s = t.slug.lowercased()
        return s.contains("playoff") || s.contains("postseason") || s.contains("post_split")
            || s.contains("cup") || s.contains("invitational") || s.contains("showdown")
    }
    func isActive(_ t: Tournament) -> Bool {
        guard let s = fmt.date(from: t.startDate) else { return false }
        if t.endDate.isEmpty { return now >= s }   // endDate 없음 = 진행 중
        guard let e = fmt.date(from: t.endDate) else { return false }
        return now >= s && now <= e
    }
    if let t = sorted.first(where: { isActive($0) && !isSpecial($0) }) { return t }
    if let t = sorted.first(where: { isActive($0) }) { return t }
    if let t = sorted.first(where: {
        guard let e = fmt.date(from: $0.endDate) else { return false }
        return e <= now && !isSpecial($0)
    }) { return t }
    return sorted.first
}
