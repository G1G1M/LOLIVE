//
//  League.swift
//  LOLIVE
//

import Foundation

struct League: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    let region: String
    let imageURL: String?

    /// Worlds/MSI처럼 연도별 히스토리가 있는 국제 대회 — 이런 리그는 LeagueDetailView가 아니라
    /// TournamentDetailView로 분기해야 한다. `.navigationDestination(for: League.self)`를
    /// 등록하는 각 탭 루트(TodayView/LeaguesView/StandingsView/PlayersView/SearchView)가
    /// 전부 이 판별 기준을 공유해야 분기가 어긋나지 않는다.
    var isInternationalTournament: Bool {
        slug == "worlds" || slug == "msi"
    }
}
