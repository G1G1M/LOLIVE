//
//  TodayViewModel+Polling.swift
//  LOLIVE
//
//  라이브 경기 폴링과 그에 딸린 처리 — 알림/Live Activity 동기화, 멈춘 피드 보정,
//  리그 로고 보강.
//

import Foundation

extension TodayViewModel {

    // MARK: - 폴링 주기

    /// 라이브 경기가 진행 중일 때. 스코어·세트가 실제로 바뀌는 구간이라 가장 짧게 잡는다.
    nonisolated static let livePollInterval: Duration = .seconds(30)
    /// 곧 시작할 경기가 있을 때. 시작을 늦게 감지해도 이 간격만큼만 밀린다.
    nonisolated static let upcomingPollInterval: Duration = .seconds(60)
    /// 라이브도 없고 임박한 경기도 없을 때.
    nonisolated static let idlePollInterval: Duration = .seconds(300)

    /// 이 시간 안에 시작하는 경기가 있으면 "임박"으로 본다.
    private nonisolated static let upcomingWindow: TimeInterval = 30 * 60

    /// 다음 폴링까지 기다릴 시간.
    ///
    /// [왜 필요한가] 예전엔 상황과 무관하게 항상 30초였다. 라이브 경기가 하나도 없는
    /// 시간대(대부분의 시간)에도 하루 2,880번을 두드리는데, 그때 `getLive` 응답은 35바이트다
    /// (실측) — 받을 게 없는데 통신만 일어난다. 응답이 작아도 매번 무선 통신을 깨우는 비용은
    /// 그대로라 배터리에 그대로 얹힌다.
    ///
    /// 늘리더라도 **경기 시작을 놓치면 안 되므로**, 예정 시각이 임박했거나 이미 지났는데
    /// 아직 시작 보고가 안 된 경기가 있으면 다시 촘촘하게 돌아온다.
    nonisolated static func pollInterval(liveCount: Int, scheduled: [Match], now: Date = Date()) -> Duration {
        if liveCount > 0 { return livePollInterval }

        var hasUpcoming = false
        for match in scheduled where match.state == .unstarted {
            let untilStart = match.startTime.timeIntervalSince(now)
            // 시작 시각이 지났는데 아직 unstarted — 조기 시작이거나 Riot API가 안 따라잡은 상태.
            // 지금이 바로 시작을 감지해야 하는 순간이라 가장 짧은 주기로 돌아간다.
            if untilStart <= 0 { return livePollInterval }
            if untilStart < upcomingWindow { hasUpcoming = true }
        }
        return hasUpcoming ? upcomingPollInterval : idlePollInterval
    }

    func startLivePolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                // 종료 감지용 스냅샷 (전체 라이브 경기 + 즐겨찾기 팀 경기)
                let prevLive = liveMatches
                let prevFavoriteLive = prevLive.filter { favoriteTeamCode(for: $0.match) != nil }

                do {
                    let live = try await service.fetchLive()
                    let newLiveIds = Set(live.map { $0.match.id })
                    let newFavoriteLive = live.filter { favoriteTeamCode(for: $0.match) != nil }

                    #if DEBUG
                    // livePollLogger.debug("🔴 [LivePoll] fetchLive 성공 — 전체 \(live.count)건, 즐겨찾기 팀 경기 \(newFavoriteLive.count)건")
                    // if newFavoriteLive.isEmpty && !favoritedTeams.isEmpty {
                    //     livePollLogger.debug("🔴 [LivePoll] 즐겨찾기 팀이 지금 getLive 응답엔 없음 (아직 시작 전이거나 API 미반영)")
                    // }
                    // for lm in newFavoriteLive {
                    //     livePollLogger.debug("🔴 [LivePoll] \(lm.match.teamA.code) \(lm.match.scoreA) - \(lm.match.scoreB) \(lm.match.teamB.code) · Game \(lm.currentSet) · state=\(lm.match.state.rawValue)")
                    // }
                    #endif

                    // 라이브에서 사라진 즐겨찾기 경기 → 결과 알림
                    // Riot이 스코어를 끝까지 안 알려준 채로(0:0) 라이브 목록에서 빠지는 경우가 실제로
                    // 있었다 — 5분 주기 보정이 미처 못 끼어든 채로 Riot이 먼저 목록에서 지워버리면
                    // "마지막으로 알던 값"이 틀린 채로 통보된다. 그래서 아직 보정이 없는 경우
                    // 사라지는 이 순간에 Leaguepedia를 한 번 더 확인해 최종 점수를 확정한다.
                    for lm in prevFavoriteLive where !newLiveIds.contains(lm.match.id) {
                        guard let code = favoriteTeamCode(for: lm.match) else { continue }
                        var finalMatch = leaguepediaOverrides[lm.match.id]
                        if finalMatch == nil {
                            finalMatch = await OracleElixirService.shared.reconcileStuckLiveMatch(lm.match)
                            if finalMatch == nil {
                                finalMatch = await LeaguepediaService.shared.reconcileStuckLiveMatch(lm.match)
                            }
                        }
                        let resolvedMatch = finalMatch ?? lm.match
                        leaguepediaOverrides[lm.match.id] = resolvedMatch
                        #if DEBUG
                        // livePollLogger.debug("🏁 [LivePoll] 라이브에서 사라짐 → 결과 알림: \(code) 최종 \(resolvedMatch.scoreA)-\(resolvedMatch.scoreB)")
                        #endif
                        await MatchNotificationService.shared.sendResultNotification(
                            for: resolvedMatch, favoriteTeamCode: code
                        )
                    }

                    // 즐겨찾기 경기의 시작/세트 진행 알림
                    // (Leaguepedia로 이미 시리즈 완료 확정된 경기는 제외 — Riot이 아직 안 따라잡아 live에 남아있어도
                    //  prevFavoriteLive엔 없으므로 "새로 시작"으로 오판하지 않도록 가드. 세트 단위 보정만 된
                    //  경기는 여전히 진행 중이라 이 루프를 계속 타야 하므로 제외하지 않는다)
                    for lm in newFavoriteLive where leaguepediaOverrides[lm.match.id]?.state != .completed {
                        guard let code = favoriteTeamCode(for: lm.match) else { continue }
                        if let prev = prevFavoriteLive.first(where: { $0.match.id == lm.match.id }) {
                            // 세트 번호가 늘었으면 이전 세트 종료 + 새 세트 시작 알림
                            if lm.currentSet > prev.currentSet {
                                #if DEBUG
                                // livePollLogger.debug("🎮 [LivePoll] 세트 변경 감지: \(code) Game \(prev.currentSet) → \(lm.currentSet), 스코어 \(lm.match.scoreA)-\(lm.match.scoreB) → 세트 종료+시작 알림 발송")
                                #endif
                                await MatchNotificationService.shared.sendSetEndNotification(
                                    for: lm.match, favoriteTeamCode: code, endedSet: prev.currentSet
                                )
                                await MatchNotificationService.shared.sendSetStartNotification(
                                    for: lm.match, favoriteTeamCode: code, newSet: lm.currentSet
                                )
                            }
                        } else {
                            // 직전 폴링엔 없었는데 지금 라이브 → 경기 시작
                            #if DEBUG
                            // livePollLogger.debug("🟢 [LivePoll] 경기 시작 감지: \(code) → 경기 시작 알림 발송")
                            #endif
                            await MatchNotificationService.shared.sendMatchStartNotification(
                                for: lm.match, favoriteTeamCode: code
                            )
                        }
                    }

                    // 라이브에서 사라진 모든 경기 → 다음 전체 스케줄 리로드 전까지도
                    // 화면에서 사라지지 않도록 로컬에서 즉시 완료 상태로 승격
                    // (즐겨찾기 경기는 위에서 이미 Leaguepedia로 최종 확정한 점수가 있으면 그걸 사용)
                    let justCompleted = prevLive
                        .filter { !newLiveIds.contains($0.match.id) }
                        .map { leaguepediaOverrides[$0.match.id] ?? $0.match }
                    for lm in prevLive where !newLiveIds.contains(lm.match.id) {
                        markCompleted(leaguepediaOverrides[lm.match.id] ?? lm.match)
                    }

                    // Riot 라이브 목록에서 스스로 빠지면(뒤늦게라도 따라잡으면) override 기록도 정리
                    leaguepediaOverrides = leaguepediaOverrides.filter { newLiveIds.contains($0.key) }
                    lastStuckCheck = lastStuckCheck.filter { newLiveIds.contains($0.key) }

                    // Leaguepedia 보정 적용: 시리즈 완료 확정은 목록에서 제외(이미 markCompleted 처리됨),
                    // 세트 단위 보정은 스코어만 교체해 계속 라이브로 표시
                    liveMatches = enrich(live).compactMap { lm -> LiveMatch? in
                        guard let override = leaguepediaOverrides[lm.match.id] else { return lm }
                        guard override.state != .completed else { return nil }
                        return LiveMatch(match: override, currentSet: lm.currentSet,
                                         lastUpdated: lm.lastUpdated, currentGameId: lm.currentGameId)
                    }
                    checkStuckLiveMatches(newFavoriteLive)

                    // 예약 시각이 지났으나 API 미확인 즐겨찾기 경기 (조기 시작 대응 + API 딜레이 브릿징)
                    let overdueMatches = todayMatches.filter {
                        $0.startTime <= Date() &&
                        $0.state == .unstarted &&
                        favoriteTeamCode(for: $0) != nil &&
                        !newLiveIds.contains($0.id)
                    }
                    await LiveActivityService.shared.syncActivities(liveMatches, overdueMatches: overdueMatches, justCompletedMatches: justCompleted, favoritedTeams: favoritedTeams)
                } catch {
                    // 폴링 중 에러는 무시 (기존 데이터 유지)
                    #if DEBUG
                    // livePollLogger.debug("⚠️ [LivePoll] fetchLive 실패: \(error.localizedDescription) — 30초 뒤 재시도")
                    #endif
                }
                // 다음 주기는 지금 상황(라이브 유무 + 임박한 경기)에 맞춰 정한다.
                let interval = Self.pollInterval(
                    liveCount: liveMatches.count,
                    scheduled: todayMatches + upcomingMatches
                )
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 즐겨찾기 변경 시 폴링 주기를 기다리지 않고 즉시 Live Activity 동기화.
    /// 최신 라이브 데이터를 직접 fetch해서 liveMatches가 오래됐거나 비어 있어도 정확히 동작.
    func syncLiveActivitiesNow() {
        syncTask?.cancel()
        let svc = service
        syncTask = Task {
            if let fresh = try? await svc.fetchLive() {
                let enriched = enrich(fresh)
                liveMatches = enriched
                let liveIds = Set(enriched.map { $0.match.id })
                let overdueMatches = todayMatches.filter {
                    $0.startTime <= Date() &&
                    $0.state == .unstarted &&
                    favoriteTeamCode(for: $0) != nil &&
                    !liveIds.contains($0.id)
                }
                await LiveActivityService.shared.syncActivities(enriched, overdueMatches: overdueMatches, favoritedTeams: favoritedTeams)
            } else {
                await LiveActivityService.shared.syncActivities(liveMatches, favoritedTeams: favoritedTeams)
            }
        }
    }

    /// 즐겨찾기 라이브 경기의 인게임 스탯 피드(feed.lolesports.com)가 멈췄는지 확인.
    ///
    /// [왜 스코어/세트 번호로 판단하지 않는가] 스코어는 한 세트가 끝나야만 바뀌는 값이라
    /// 정상 진행 중에도 20~40분씩 그대로인 게 당연하다 — 그걸로 "멈춤"을 판단하면
    /// 멀쩡히 진행 중인 경기까지 전부 오탐하게 된다. 대신 인게임 피드의 gameState/최신 프레임
    /// 시각을 직접 확인해서, `"finished"`가 명시적으로 찍혀 있거나 오래 조용할 때만 "멈췄다"고 판단한다.
    ///
    /// 멈춘 것으로 확인되면 Leaguepedia MatchSchedule과 대조한다 — 이 테이블은 시리즈가 안 끝나도
    /// Team1Score/Team2Score를 세트가 끝날 때마다 갱신해주므로 부분 스코어(예: 0-1)도 반영 가능하다.
    /// 이전에 이미 반영한 것과 스코어가 같으면(Leaguepedia도 아직 그대로) 재알림을 보내지 않는다.
    /// 아무 데도 없으면 억지로 점수를 만들어내지 않고 다음 쿨다운에 재시도한다.
    func checkStuckLiveMatches(_ favoriteLive: [LiveMatch]) {
        for lm in favoriteLive {
            guard let gameId = lm.currentGameId else { continue }
            guard leaguepediaOverrides[lm.match.id]?.state != .completed else { continue }
            let lastCheck = lastStuckCheck[lm.match.id]
            guard lastCheck == nil || Date().timeIntervalSince(lastCheck!) > Self.stuckRecheckCooldown else { continue }
            lastStuckCheck[lm.match.id] = Date()

            let match = lm.match
            let currentSet = lm.currentSet
            let stats = liveStatsService
            let previousScore = leaguepediaOverrides[match.id].map { ($0.scoreA, $0.scoreB) }
                ?? (match.scoreA, match.scoreB)
            Task {
                let recentWindowStart = Date().addingTimeInterval(-(Self.staleFeedThreshold + 5 * 60))
                guard let window = try? await stats.fetchGameWindow(gameId: gameId, startingTime: recentWindowStart)
                else { return }
                let isFinished = window.gameState == "finished"
                let isStale = window.lastFrameTimestamp
                    .map { Date().timeIntervalSince($0) > Self.staleFeedThreshold } ?? true
                guard isFinished || isStale else { return }

                var reconciled = await OracleElixirService.shared.reconcileStuckLiveMatch(match)
                if reconciled == nil {
                    reconciled = await LeaguepediaService.shared.reconcileStuckLiveMatch(match)
                }
                guard let updated = reconciled else { return }
                let newScore = (updated.scoreA, updated.scoreB)
                guard newScore != previousScore else { return }  // 둘 다 아직 그대로면 조용히 재시도만

                leaguepediaOverrides[match.id] = updated
                if updated.state == .completed {
                    liveMatches.removeAll { $0.match.id == match.id }
                    markCompleted(updated)
                    if let code = favoriteTeamCode(for: updated) {
                        await MatchNotificationService.shared.sendResultNotification(for: updated, favoriteTeamCode: code)
                    }
                } else if let code = favoriteTeamCode(for: updated) {
                    await MatchNotificationService.shared.sendSetEndNotification(
                        for: updated, favoriteTeamCode: code, endedSet: currentSet
                    )
                }
            }
        }
    }

    func enrich(_ live: [LiveMatch]) -> [LiveMatch] {
        let map = Dictionary(uniqueKeysWithValues: cachedLeagues.map { ($0.id, $0.imageURL) })
        return live.map { lm in
            guard let imageURL = map[lm.match.league.id] else { return lm }
            let enrichedLeague = League(
                id: lm.match.league.id, slug: lm.match.league.slug,
                name: lm.match.league.name,
                region: lm.match.league.region, imageURL: imageURL
            )
            let enrichedMatch = Match(
                id: lm.match.id, league: enrichedLeague,
                teamA: lm.match.teamA, teamB: lm.match.teamB,
                scoreA: lm.match.scoreA, scoreB: lm.match.scoreB,
                startTime: lm.match.startTime, state: lm.match.state,
                blockName: lm.match.blockName
            )
            return LiveMatch(match: enrichedMatch, currentSet: lm.currentSet, lastUpdated: lm.lastUpdated, currentGameId: lm.currentGameId)
        }
    }
}
