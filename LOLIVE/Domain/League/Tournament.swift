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

/// Tournament.startDate/endDate("2025-01-15") 전용 공유 포매터.
/// DateFormatter 생성은 비싸서, 이 형식을 쓰는 곳은 전부 이 인스턴스를 재사용한다
/// (읽기 전용 사용은 스레드 세이프 — 백그라운드 캐시 선로딩 경로에서도 그대로 쓴다).
let tournamentDayFormatter: DateFormatter = {
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
    let fmt = tournamentDayFormatter
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

/// LCK처럼 스플릿이 바뀌어도 리셋되지 않고 누적되는 순위표(레전드/라이즈 그룹)를 계산할 때 쓰는
/// 집계 시작일. "같은 해 첫 스플릿부터 전부"로 했더니 실측(Leaguepedia 실제 표)보다 경기 수가
/// 훨씬 많이 나왔다 — 확인해보니 스플릿마다 대회 형식 자체가 다르다(예: 2026 LCK는 Split 1이
/// "알파/오메가 그룹", Split 2가 "그룹 없는 단일 정규리그", Split 3이 "레전드/라이즈 그룹"으로
/// 서로 다른 스테이지 구조). 실측 경기 수와 대조해보니 "바로 직전 스플릿부터 현재 스플릿까지"가
/// 잘 맞아서, 같은 해 첫 스플릿이 아니라 활성 스플릿 바로 이전(시작일 기준) 정규 스플릿의 시작일을
/// 쓴다. 이전 스플릿이 없으면(그 해 첫 스플릿이 곧 활성 스플릿) 활성 스플릿 자체의 시작일로 폴백.
func seasonStartDate(from tournaments: [Tournament], active: Tournament) -> Date {
    let fmt = tournamentDayFormatter
    guard let activeStart = fmt.date(from: active.startDate) else { return .distantPast }

    let previousStarts = tournaments.compactMap { t -> Date? in
        guard !isSpecialTournament(t), t.id != active.id,
              let d = fmt.date(from: t.startDate), d < activeStart
        else { return nil }
        return d
    }
    return previousStarts.max() ?? activeStart
}
