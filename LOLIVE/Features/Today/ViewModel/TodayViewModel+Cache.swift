//
//  TodayViewModel+Cache.swift
//  LOLIVE
//
//  네트워크 응답 전에 디스크 캐시로 화면을 먼저 채우는 선로딩 경로.
//  디스크 읽기는 detached Task에서 하고, 결과만 메인 액터로 옮긴다.
//

import Foundation

extension TodayViewModel {

    /// 캐시 프리로드 결과 — readDiskPreload()가 백그라운드에서 읽어온 값을 메인 액터로 옮길 때 쓰는 그릇.
    private struct DiskPreload {
        let leagues: [League]
        let matches: [Match]
    }

    /// 리그 목록만큼 스케줄 캐시 파일을 읽어 하나로 합친다.
    ///
    /// 이 앱은 추적 중인 리그가 45개라, 실제 캐시를 재보면 파일 45개·합계 4.2MB를 한 번에
    /// 읽고 디코딩한다(맥에서 45ms, 실기기 환산 100ms 내외). 그래서 반드시 메인 스레드 밖에서
    /// 돌려야 한다 — `nonisolated`인 이유.
    nonisolated static func readCachedSchedules(for leagues: [League], stale: Bool) -> [Match] {
        var all: [Match] = []
        for league in leagues {
            let matches: [Match]? = stale
                ? AppDiskCache.getStale(.schedule(leagueId: league.id))
                : AppDiskCache.get(.schedule(leagueId: league.id))
            if let matches { all.append(contentsOf: matches) }
        }
        return all
    }

    private nonisolated static func readDiskPreload(stale: Bool) -> DiskPreload? {
        let leagues: [League]? = stale
            ? AppDiskCache.getStale(.leagues)
            : AppDiskCache.get(.leagues)
        guard let leagues else { return nil }
        return DiskPreload(leagues: leagues, matches: readCachedSchedules(for: leagues, stale: stale))
    }

    /// 앱을 켠 직후 호출된다 — 여기서 메인 스레드가 막히면 첫 화면이 그리는 시점 자체가 밀리므로
    /// 파일 읽기·디코딩 전체를 detached Task로 내보내고, 화면에 반영하는 부분만 메인에서 한다.
    func preloadFromCache() async -> Bool {
        let preload = await Task.detached(priority: .userInitiated) {
            Self.readDiskPreload(stale: false)
        }.value
        guard let result = preload else { return false }
        cachedLeagues = result.leagues
        classify(matches: result.matches)
        return true
    }

    func loadFromStaleCache() async -> Bool {
        let preload = await Task.detached(priority: .userInitiated) {
            Self.readDiskPreload(stale: true)
        }.value
        guard let result = preload else { return false }
        guard !result.matches.isEmpty else { return false }
        cachedLeagues = result.leagues
        classify(matches: result.matches)
        return true
    }
}
