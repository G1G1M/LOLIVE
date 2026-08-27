//
//  MatchDetailViewModel+Cache.swift
//  LOLIVE
//
//  디스크/서버 캐시에서 경기 상세를 되살리는 경로와, 킬 타임라인·밴 데이터 보강.
//

import Foundation
import os

extension MatchDetailViewModel {

    func tryLoadFromCache() async -> Bool {
        guard let detail: EventDetailInfo = AppDiskCache.get(.eventDetail(matchId: match.id)),
              Self.isGenuinelyComplete(detail)
        else { return false }

        eventDetail = detail
        selectedGameId = detail.games.last(where: { $0.state.isPlayable })?.gameId

        let cache = GameWindowCache.shared
        for game in detail.games.filter({ $0.state.isPlayable }) {
            if let window = await cache.window(for: game.gameId) {
                gameWindows[game.gameId] = window
            }
        }

        for game in detail.games.filter({ $0.state.isPlayable }) {
            if let cached: [KillEvent] = AppDiskCache.get(
                key: "kill_timeline_\(game.gameId)", maxAge: 30 * 24 * 3600) {
                killTimelines[game.gameId] = cached
            }
        }

        #if DEBUG
        Self.navDebugLogger.debug("🔍 [NavDebug] fetchGameBans 호출 직전 matchId=\(self.match.id)")
        #endif
        await fetchGameBans(for: detail.games.filter { $0.state == .completed })
        #if DEBUG
        Self.navDebugLogger.debug("🔍 [NavDebug] fetchGameBans 호출 완료 matchId=\(self.match.id) isCancelled=\(Task.isCancelled)")
        #endif
        return true
    }

    /// 서버(getMatchDetail Callable)에 이 경기의 상세가 이미 캐싱돼 있으면 그걸 디스크에
    /// 저장하고 tryLoadFromCache()로 나머지(게임 윈도우 등)까지 일관되게 로딩한다.
    func tryLoadFromServerCache() async -> Bool {
        guard let detail = await FirebaseMatchDetailService.fetchCachedDetail(matchId: match.id),
              Self.isGenuinelyComplete(detail)
        else { return false }
        AppDiskCache.set(.eventDetail(matchId: match.id), value: detail)
        return await tryLoadFromCache()
    }

    func loadKillTimelines(for games: [GameInfo], liveStats: LiveStatsServiceProtocol) async {
        await withTaskGroup(of: (String, [KillEvent]).self) { group in
            for game in games {
                let gameId = game.gameId
                let isCompleted = game.state == .completed
                group.addTask {
                    if isCompleted,
                       let cached: [KillEvent] = AppDiskCache.get(
                           key: "kill_timeline_\(gameId)", maxAge: 30 * 24 * 3600) {
                        return (gameId, cached)
                    }
                    let events = (try? await liveStats.fetchKillTimeline(gameId: gameId)) ?? []
                    if !events.isEmpty && isCompleted {
                        AppDiskCache.set(key: "kill_timeline_\(gameId)", value: events)
                    }
                    return (gameId, events)
                }
            }
            for await (gameId, events) in group {
                if !events.isEmpty { killTimelines[gameId] = events }
            }
        }
    }

    /// Riot이 밴을 안 주는 완료 경기의 밴 조회 — Oracle's Elixir(`/drafts`)를 먼저 시도하고,
    /// 실패한 게임만 Leaguepedia로 폴백한다.
    func fetchGameBans(for games: [GameInfo]) async {
        let matchId = match.id
        await withTaskGroup(of: (String, (blue: [String], red: [String])?).self) { group in
            for game in games {
                guard game.blueBans.isEmpty && game.redBans.isEmpty else { continue }
                let gameId = game.gameId
                let number = game.number
                group.addTask {
                    let bans = await OracleElixirService.shared.fetchDraftBans(riotMatchId: matchId, gameNumber: number)
                    return (gameId, bans)
                }
            }
            for await (gameId, bans) in group {
                guard !Task.isCancelled else { continue }
                if let bans {
                    #if DEBUG
                    Self.navDebugLogger.debug("🔍 [NavDebug] oeBans 갱신 matchId=\(self.match.id) gameId=\(gameId)")
                    #endif
                    self.oeBans[gameId] = bans
                }
            }
        }

        let remaining = games.filter {
            self.oeBans[$0.gameId] == nil && $0.blueBans.isEmpty && $0.redBans.isEmpty
        }
        guard !remaining.isEmpty else { return }

        let lpService = leaguepediaService
        await withTaskGroup(of: (String, (team1Bans: [String], team2Bans: [String])?).self) { group in
            for game in remaining {
                let gameId = game.gameId
                group.addTask {
                    let bans = await lpService.fetchBans(riotGameId: gameId)
                    return (gameId, bans)
                }
            }
            for await (gameId, bans) in group {
                // Leaguepedia 호출(레이트리밋으로 지연될 수 있음)이 끝나기 전에 사용자가 화면을
                // 벗어나면(뒤로가기) 응답이 뒤늦게 와도 상태를 건드리면 안 된다 — 완료 경기 상세만
                // 이 밴 조회를 거치는데, 하필 이게 늦게 끝나서 뒤로가기 전환 도중 상태 갱신이 겹치며
                // ScrollView가 맨 위로 리셋되는 것처럼 보이는 문제가 있었다(실측 확인).
                guard !Task.isCancelled else { continue }
                if let bans {
                    #if DEBUG
                    Self.navDebugLogger.debug("🔍 [NavDebug] leaguepediaBans 갱신 matchId=\(self.match.id) gameId=\(gameId)")
                    #endif
                    self.leaguepediaBans[gameId] = bans
                }
            }
        }
    }
}
