//
//  LeagueDetailViewModel+Cache.swift
//  LOLIVE
//
//  네트워크 응답 전에 디스크 캐시로 화면을 먼저 채우는 선로딩 경로.
//  디스크 읽기는 detached Task에서 하고, 결과만 메인 액터로 옮긴다.
//

import Foundation

extension LeagueDetailViewModel {

    /// 캐시 프리로드 결과 — readDiskPreload()가 백그라운드에서 읽어온 값을 메인 액터로 옮길 때 쓰는 그릇.
    private struct DiskPreload {
        let upcomingMatches: [Match]
        let completedMatches: [Match]
        let standings: [Standing]?
        let players: [Player]?
    }

    /// 캐시 파일 읽기(동기 디스크 I/O + JSON 디코딩, 최대 5개 파일)를 메인 스레드 밖에서 수행한다.
    /// 예전엔 이 로직 전체가 메인 액터(`preloadFromCache()`)에서 그대로 동기 실행돼서, 리그 상세
    /// 화면으로 들어가는 NavigationStack push 애니메이션이 시작되는 바로 그 순간(`.task`가 뷰
    /// 등장과 동시에 호출됨) 메인 스레드가 여러 번의 파일 읽기로 막혀 전환이 뚝뚝 끊기는 문제가
    /// 있었음(리그 상세는 일정+토너먼트+순위+선수까지 한 번에 읽어서 다른 화면보다 유독 무거움).
    private nonisolated static func readDiskPreload(league: League, stale: Bool) -> DiskPreload? {
        let allMatches: [Match]? = stale
            ? AppDiskCache.getStale(.schedule(leagueId: league.id))
            : AppDiskCache.get(.schedule(leagueId: league.id))
        guard let allMatches else { return nil }

        let now = Date()
        let upcoming = allMatches
            .filter { $0.startTime >= now && $0.state == .unstarted }
            .sorted { $0.startTime < $1.startTime }
        let completed = allMatches
            .filter { $0.state == .completed }
            .sorted { $0.startTime > $1.startTime }

        var standings: [Standing]? = nil
        let tournaments: [Tournament]? = stale
            ? AppDiskCache.getStale(.tournaments(leagueId: league.id))
            : AppDiskCache.get(.tournaments(leagueId: league.id))
        if let tournaments, let tournament = activeTournament(from: tournaments) {
            let fetched: [Standing]? = stale
                ? AppDiskCache.getStale(.standings(tournamentId: tournament.id))
                : AppDiskCache.get(.standings(tournamentId: tournament.id))
            if let fetched {
                let seasonMatches: [Match] = (stale
                    ? AppDiskCache.getStale(.allSchedule(leagueId: league.id))
                    : AppDiskCache.get(.allSchedule(leagueId: league.id))) ?? allMatches
                standings = Standing.reconciled(
                    fetched, schedule: seasonMatches,
                    seasonStartDate: seasonStartDate(from: tournaments, active: tournament)
                )
            }
        }

        // stale 경로는 예전에도 선수 캐시를 안 읽었음(원본 동작 유지)
        let players: [Player]? = stale ? nil
            : AppDiskCache.get(key: "league_players_\(league.id)", maxAge: 12 * 3600)

        return DiskPreload(upcomingMatches: upcoming, completedMatches: completed, standings: standings, players: players)
    }

    func preloadFromCache() async -> Bool {
        guard let result = await Task.detached(priority: .userInitiated) { [league] in
            Self.readDiskPreload(league: league, stale: false)
        }.value else { return false }
        upcomingMatches = result.upcomingMatches
        completedMatches = result.completedMatches
        if let standings = result.standings { self.standings = standings }
        if let players = result.players { self.players = players }
        return true
    }

    func preloadFromStaleCache() async -> Bool {
        guard let result = await Task.detached(priority: .userInitiated) { [league] in
            Self.readDiskPreload(league: league, stale: true)
        }.value else { return false }
        upcomingMatches = result.upcomingMatches
        completedMatches = result.completedMatches
        if let standings = result.standings { self.standings = standings }
        return true
    }

    /// GD·승패를 완료 경기 스코어로 직접 재계산 — 자세한 이유는 Standing.reconciled(_:schedule:) 참고.
    func applyGD(_ standings: [Standing], schedule: [Match], seasonStartDate: Date) -> [Standing] {
        Standing.reconciled(standings, schedule: schedule, seasonStartDate: seasonStartDate)
    }

}
