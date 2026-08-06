//
//  MatchDetailView.swift
//  LOLIVE
//
//  경기 상세 화면. 드래프트(+Draft), 인게임 스탯(+Stats), 킬 타임라인(+Timeline)은
//  같은 이름의 extension 파일로 분리되어 있다.
//

import SwiftUI

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
                }
                .padding()
            }
        }
        .navigationTitle(match.league.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Score Card

    private var scoreCard: some View {
        VStack(spacing: 20) {
            statusBadge

            HStack(spacing: 0) {
                teamColumn(team: resolvedTeam(match.teamA), isWinner: match.scoreA > match.scoreB)
                scoreColumn
                teamColumn(team: resolvedTeam(match.teamB), isWinner: match.scoreB > match.scoreA)
            }
        }
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func teamColumn(team: Team, isWinner: Bool) -> some View {
        NavigationLink {
            TeamDetailView(team: team, league: match.league)
        } label: {
            VStack(spacing: 8) {
                CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                    .frame(width: 64, height: 64)

                Text(team.name)
                    .font(.subheadline)
                    .fontWeight(isWinner ? .bold : .regular)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(team.code)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var scoreColumn: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text("\(match.scoreA)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(match.scoreA > match.scoreB ? .primary : .secondary)
                Text("-")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("\(match.scoreB)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(match.scoreB > match.scoreA ? .primary : .secondary)
            }

            if let live = liveMatch {
                Text("Game \(live.currentSet) 진행 중")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch match.state {
        case .inProgress:
            VStack(spacing: 4) {
                LiveBadge()

                if let t = viewModel.lastPolledAt {
                    Text("\(match.league.name) · 업데이트 \(t, style: .relative) 전")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(match.league.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

        case .completed:
            let dateText = match.startTime.formatted(
                .dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR"))
            )
            VStack(spacing: 4) {
                Text("경기 종료")
                    .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15)).clipShape(Capsule())
                Text("\(match.league.name) · \(dateText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

        case .unstarted:
            VStack(spacing: 4) {
                Text(match.startTime.formatted(
                    .dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR"))
                ))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1)).clipShape(Capsule())

                Text(match.league.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
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
