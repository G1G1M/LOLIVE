//
//  MatchDetailView.swift
//  LOLIVE
//
//  경기 상세 화면. 드래프트(+Draft), 인게임 스탯(+Stats), 킬 타임라인(+Timeline)은
//  같은 이름의 extension 파일로 분리되어 있다.
//

import SwiftUI
import os

private let navDebugLogger = Logger(subsystem: "com.lolive", category: "NavDebug")

struct MatchDetailView: View {
    let match: Match
    var liveMatch: LiveMatch? = nil

    @State var viewModel: MatchDetailViewModel
    @State var isPulsing = false

    init(match: Match, liveMatch: LiveMatch? = nil) {
        self.match = match
        self.liveMatch = liveMatch
        self._viewModel = State(initialValue: MatchDetailViewModel(match: match))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    scoreCard

                    if viewModel.isLoading {
                        LoadingView("데이터 불러오는 중...")
                            .frame(minHeight: 120)
                    } else if let error = viewModel.errorMessage {
                        ErrorRetryView(error) { Task { await viewModel.load() } }
                            .frame(minHeight: 160)
                    } else if match.state == .unstarted && viewModel.eventDetail == nil {
                        upcomingCard
                    } else if let detail = viewModel.eventDetail {
                        if detail.games.filter({ $0.state != .unneeded }).count > 1 {
                            gameSeriesPicker(detail: detail)
                        }

                        if let game = viewModel.selectedGame {
                            let bans = viewModel.correctedBans(for: game)
                            if !bans.blue.isEmpty || !bans.red.isEmpty {
                                banCard(game: game, blueBans: bans.blue, redBans: bans.red)
                            } else if game.state == .unstarted {
                                draftWaitingCard
                            }
                        }

                        if let window = viewModel.selectedGameWindow {
                            let gameIsLive = viewModel.selectedGame?.state == .inProgress
                            if window.hasLiveStats || gameIsLive {
                                teamStatsCard(window: window)
                                playerListCard(window: window)
                            } else {
                                playerListCard(window: window)
                                noStatsCard
                            }
                            let kills = viewModel.selectedGame.flatMap { viewModel.killTimelines[$0.gameId] } ?? []
                            if !kills.isEmpty {
                                killTimelineCard(window: window, kills: kills)
                            }
                        } else if let game = viewModel.selectedGame, game.state != .unstarted {
                            // window가 nil인 진짜 실패 케이스만 여기로 옴(unstarted는 위 draftWaitingCard가 이미 처리).
                            statsUnavailableCard
                        }
                    }

                    matchInfoSection
                }
                .padding()
            }
        }
        .navigationTitle(match.league.name)
        .navigationBarTitleDisplayMode(.inline)
        // matchInfoSection의 리그 링크는 값 기반(NavigationLink(value:))으로 통일했다 — 예전엔
        // 클로저 방식(NavigationLink { View })을 썼는데, 이 화면 자체가
        // .navigationDestination(for: Match.self)라는 값 기반 방식으로 진입해 있어서 두 방식이
        // 섞이자 리그에서 뒤로가기로 돌아올 때 SwiftUI가 이 화면을 "새 화면"으로 통째로 다시
        // 만들어버렸음(실측 확인). League.self 목적지 핸들러는 여기서 등록하지 않는다 — League도
        // Match처럼 자기 완결적이라 각 탭 루트에서 한 번만 등록하면 되는데, 여기서도 등록하면 이
        // 화면이 LeaguesView 스택에 중첩될 때(리그 목록 → 리그 상세 → 경기 상세) 중복 등록된다.
        .task(id: match.id) {
            await viewModel.load()
            viewModel.startPolling()
        }
        .onAppear {
            #if DEBUG
            navDebugLogger.debug("🔍 [NavDebug] MatchDetailView onAppear matchId=\(match.id)")
            #endif
        }
        .onDisappear {
            #if DEBUG
            navDebugLogger.debug("🔍 [NavDebug] MatchDetailView onDisappear matchId=\(match.id)")
            #endif
            viewModel.stopPolling()
        }
    }

    // MARK: - Score Card

    private var scoreCard: some View {
        HStack(spacing: 0) {
            teamColumn(team: resolvedTeam(match.teamA), isWinner: match.scoreA > match.scoreB)
            scoreColumn
            teamColumn(team: resolvedTeam(match.teamB), isWinner: match.scoreB > match.scoreA)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func teamColumn(team: Team, isWinner: Bool) -> some View {
        NavigationLink {
            TeamDetailView(team: team, league: match.league)
        } label: {
            VStack(spacing: 10) {
                LogoBadgeView(imageURL: team.imageURL, size: 48)

                Text(team.code)
                    .font(.footnote)
                    .fontWeight(isWinner ? .bold : .regular)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var scoreColumn: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("\(match.scoreA)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(match.scoreA > match.scoreB ? .primary : .secondary)
                Text("-")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
                Text("\(match.scoreB)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(match.scoreB > match.scoreA ? .primary : .secondary)
            }

            statusText
        }
        .frame(width: 120)
    }

    /// 팀 로고/이름 행과 같은 줄에 오는 짧은 상태 텍스트 (LIVE / 경기 종료 / 예정 시각).
    /// 리그명·날짜 같은 부가 정보는 matchInfoSection(페이지 맨 아래)으로 분리했다.
    @ViewBuilder
    private var statusText: some View {
        switch match.state {
        case .inProgress:
            LiveBadge()
        case .completed:
            Text("경기 종료")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unstarted:
            Text(match.startTime.formatted(
                .dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR"))
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Match Info Section (리그 · 날짜/업데이트 시각 — 페이지 맨 아래)

    private var matchInfoSection: some View {
        VStack(spacing: 4) {
            NavigationLink(value: match.league) {
                HStack(spacing: 3) {
                    Text(match.league.name)
                        .font(.subheadline).fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            infoSubtext
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var infoSubtext: some View {
        switch match.state {
        case .inProgress:
            VStack(spacing: 2) {
                if let live = liveMatch {
                    Text("Game \(live.currentSet) 진행 중")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let t = viewModel.lastPolledAt {
                    Text("업데이트 \(t, style: .relative) 전")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        case .completed:
            Text(match.startTime.formatted(
                .dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR"))
            ))
            .font(.caption).foregroundStyle(.secondary)
        case .unstarted:
            EmptyView()
        }
    }

    // MARK: - Upcoming Card

    private var upcomingCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("경기 예정")
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(match.startTime.formatted(
                .dateTime.month().day().weekday().hour().minute()
                .locale(Locale(identifier: "ko_KR"))
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Shared Helpers (+Draft/+Stats/+Timeline에서도 사용)

    /// window의 esports 팀 ID로 match 팀을 반환.
    /// eventDetail의 esports ID → match 팀 코드 순으로 매칭.
    func teamFor(windowTeamId: String) -> Team? {
        guard !windowTeamId.isEmpty else { return nil }
        if let detail = viewModel.eventDetail {
            if detail.teamAEsportsId == windowTeamId { return match.teamA }
            if detail.teamBEsportsId == windowTeamId { return match.teamB }
        }
        if match.teamA.id == windowTeamId || match.teamA.code == windowTeamId { return match.teamA }
        if match.teamB.id == windowTeamId || match.teamB.code == windowTeamId { return match.teamB }
        return nil
    }

    func formatGold(_ gold: Int) -> String {
        gold >= 1000 ? String(format: "%.1fk", Double(gold) / 1000) : "\(gold)"
    }

    // MARK: - Private Helpers (이 파일에서만 사용)

    /// getSchedule에서 누락된 esports 팀 ID를 eventDetail 값으로 보완한 Team 반환.
    /// TeamDetailView.load()에서 fetchTeamRoster가 올바른 ID로 호출되도록 보장.
    private func resolvedTeam(_ team: Team) -> Team {
        guard let detail = viewModel.eventDetail else { return team }
        let esportsId = (team.code == match.teamA.code) ? detail.teamAEsportsId : detail.teamBEsportsId
        guard !esportsId.isEmpty, esportsId != team.id else { return team }
        return Team(id: esportsId, name: team.name, code: team.code, imageURL: team.imageURL)
    }
}


#Preview {
    let league = League(id: "1", slug: "lck", name: "LCK", region: "Korea", imageURL: nil)
    let t1  = Team(id: "t1",  name: "T1",    code: "T1",  imageURL: nil)
    let gen = Team(id: "gen", name: "Gen.G", code: "GEN", imageURL: nil)
    let match = Match(id: "m1", league: league, teamA: t1, teamB: gen,
                      scoreA: 2, scoreB: 1, startTime: Date(), state: .completed)

    NavigationStack {
        MatchDetailView(match: match)
    }
    .preferredColorScheme(.dark)
}
