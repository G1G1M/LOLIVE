//
//  TodayViewModel+Cache.swift
//  LOLIVE
//
//  네트워크 응답 전에 디스크 캐시로 화면을 먼저 채우는 선로딩 경로.
//  API가 실패했을 땐 만료된 캐시라도 꺼내 빈 화면 대신 보여준다.
//

import Foundation

extension TodayViewModel {

    func preloadFromCache() -> Bool {
        guard let leagues: [League] = AppDiskCache.get(.leagues) else { return false }
        var allMatches: [Match] = []
        for league in leagues {
            if let matches: [Match] = AppDiskCache.get(.schedule(leagueId: league.id)) {
                allMatches.append(contentsOf: matches)
            }
        }
        cachedLeagues = leagues
        classify(matches: allMatches)
        return true
    }

    func loadFromStaleCache() -> Bool {
        guard let leagues: [League] = AppDiskCache.getStale(.leagues) else { return false }
        var allMatches: [Match] = []
        for league in leagues {
            if let matches: [Match] = AppDiskCache.getStale(.schedule(leagueId: league.id)) {
                allMatches.append(contentsOf: matches)
            }
        }
        guard !allMatches.isEmpty else { return false }
        cachedLeagues = leagues
        classify(matches: allMatches)
        return true
    }
}
