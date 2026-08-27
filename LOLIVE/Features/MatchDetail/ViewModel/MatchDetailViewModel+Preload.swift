//
//  MatchDetailViewModel+Preload.swift
//  LOLIVE
//
//  경기 목록 화면에서 완료 경기 상세를 백그라운드로 미리 캐싱하는 정적 진입점.
//  화면 인스턴스와 무관하게 도는 코드라 ViewModel 본체와 분리해 둔다.
//

import Foundation

extension MatchDetailViewModel {

    /// 경기 목록 화면에서 완료된 경기 데이터를 백그라운드로 미리 캐싱.
    /// 이미 캐시된 경기는 건너뜀.
    static func preload(match: Match) {
        guard match.state == .completed, !isBackfilledMatchId(match.id) else { return }
        let detailKey = CacheKey.eventDetail(matchId: match.id)
        guard (AppDiskCache.get(detailKey) as EventDetailInfo?) == nil else { return }

        Task.detached(priority: .background) {
            let esports = RiotEsportsService()
            let liveStats = LiveStatsService()

            let detail: EventDetailInfo
            if let serverDetail = await FirebaseMatchDetailService.fetchCachedDetail(matchId: match.id),
               isGenuinelyComplete(serverDetail) {
                detail = serverDetail
            } else if let riotDetail = try? await esports.fetchEventDetails(matchId: match.id),
                      isGenuinelyComplete(riotDetail) {
                // 아직 안 채워진 상태면 캐싱 안 하고 넘어감 — 다음 preload 시도(스케줄 새로고침마다)에
                // 다시 확인해서, Riot/서버가 채워주는 대로 자연스럽게 잡히게 한다.
                detail = riotDetail
            } else {
                return
            }
            AppDiskCache.set(detailKey, value: detail)

            let cache = GameWindowCache.shared
            let startTime = match.startTime
            await withTaskGroup(of: Void.self) { group in
                for game in detail.games where game.state == .completed {
                    let gid = game.gameId
                    let num = game.number
                    group.addTask {
                        guard await cache.window(for: gid) == nil else { return }
                        if let w = try? await liveStats.fetchGameWindow(gameId: gid, startingTime: nil),
                           w.hasLiveStats {
                            await cache.save(w); return
                        }
                        let base = 20.0 + Double(num - 1) * 70.0
                        var best: (Double, GameWindow)? = nil
                        await withTaskGroup(of: (Double, GameWindow?).self) { inner in
                            for extra in [55.0, 45.0, 35.0, 20.0] {
                                let t = startTime.addingTimeInterval((base + extra) * 60)
                                inner.addTask {
                                    let w = try? await liveStats.fetchGameWindow(gameId: gid, startingTime: t)
                                    return (base + extra, w?.hasLiveStats == true ? w : nil)
                                }
                            }
                            for await (k, w) in inner {
                                if let w, best == nil || k > best!.0 { best = (k, w) }
                            }
                        }
                        if let w = best?.1 { await cache.save(w) }
                    }
                }
            }
        }
    }
}
