//
//  AppPreloadService.swift
//  LOLIVE
//

import Foundation

/// 앱 시작 시 1군 리그 경기 상세 데이터를 백그라운드로 선제 캐싱.
/// 이미 캐시된 데이터는 건너뛰므로 첫 실행 후에는 API 호출 최소화.
final class AppPreloadService {

    static let shared = AppPreloadService()
    private var hasStarted = false

    private let primaryLeagueIDs: Set<String> = [
        "98767991310872058",  // LCK
        "98767991314006698",  // LPL
        "98767991302996019",  // LEC
        "98767991299243165",  // LCS
        "104366947889790212", // PCS
        "107213827295848783", // VCS
        "98767991332355509",  // CBLOL
        "98767991349978712",  // LJL
        "105709090213554609", // LCO
        "101382741235120470", // LLA
        "113476371197627891", // LCP
    ]

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        Task.detached(priority: .background) {
            await self.run()
        }
    }

    private func run() async {
        // UI가 완전히 렌더링된 후 시작
        try? await Task.sleep(for: .seconds(3))

        let service = RiotEsportsService()

        // 1. 리그 목록 (캐시 우선)
        let leagues: [League]
        if let cached: [League] = AppDiskCache.get(key: "leagues", maxAge: 24 * 3600), !cached.isEmpty {
            leagues = cached
        } else {
            guard let fetched = try? await service.fetchLeagues(), !fetched.isEmpty else { return }
            AppDiskCache.set(key: "leagues", value: fetched)
            leagues = fetched
        }

        let primaryLeagues = leagues.filter { primaryLeagueIDs.contains($0.id) }

        // 2. 리그별 일정 로드 후 완료 경기 프리로드
        for league in primaryLeagues {
            let schedule: [Match]
            if let cached: [Match] = AppDiskCache.get(key: "schedule_\(league.id)", maxAge: 15 * 60) {
                schedule = cached
            } else {
                guard let fetched = try? await service.fetchSchedule(league: league) else { continue }
                schedule = fetched
            }

            let completed = schedule
                .filter { $0.state == .completed }
                .sorted { $0.startTime > $1.startTime }

            for match in completed.prefix(8) {
                MatchDetailViewModel.preload(match: match)
            }
        }
    }
}
