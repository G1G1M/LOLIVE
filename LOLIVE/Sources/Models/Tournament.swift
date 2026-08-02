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

private let tournamentDateFormat: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    return fmt
}()

/// "플레이오프/컵/이벤트" 성격의 특수 대회 — 정규 스플릿과 구분해야 하는 곳에서 공통으로 씀.
private func isSpecialTournament(_ t: Tournament) -> Bool {
    let s = t.slug.lowercased()
    return s.contains("playoff") || s.contains("postseason") || s.contains("post_split")
        || s.contains("cup") || s.contains("invitational") || s.contains("showdown")
}

/// 토너먼트 목록에서 현재 진행 중인 가장 적합한 토너먼트를 반환.
/// 1순위: 진행 중인 정규시즌 / 2순위: 진행 중인 플레이오프 / 3순위: 가장 최근 완료된 정규시즌 / 4순위: 가장 최근 토너먼트
func activeTournament(from tournaments: [Tournament]) -> Tournament? {
    let fmt = tournamentDateFormat
    let now = Date()
    let sorted = tournaments.sorted {
        (fmt.date(from: $0.startDate) ?? .distantPast) >
        (fmt.date(from: $1.startDate) ?? .distantPast)
    }
    let isSpecial = isSpecialTournament
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

/// `active` 토너먼트와 같은 해에 시작한 "특수 대회가 아닌"(정규 스플릿) 토너먼트 중 가장 이른
/// 시작일을 시즌 시작일로 본다. LCK처럼 스플릿이 바뀌어도 리셋되지 않고 누적되는 순위표
/// (레전드/라이즈 그룹)를 계산할 때, 이 시점 이후의 완료 경기를 전부 합산하는 기준으로 쓴다.
func seasonStartDate(from tournaments: [Tournament], active: Tournament) -> Date {
    let fmt = tournamentDateFormat
    guard let activeStart = fmt.date(from: active.startDate) else { return .distantPast }
    let year = Calendar.current.component(.year, from: activeStart)
    let sameYearStarts = tournaments.compactMap { t -> Date? in
        guard !isSpecialTournament(t), let d = fmt.date(from: t.startDate) else { return nil }
        return Calendar.current.component(.year, from: d) == year ? d : nil
    }
    return sameYearStarts.min() ?? activeStart
}
