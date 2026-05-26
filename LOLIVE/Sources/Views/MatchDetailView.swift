//
//  MatchDetailView.swift
//  LOLIVE
//

import SwiftUI

struct MatchDetailView: View {
    let match: Match
    var liveMatch: LiveMatch? = nil

    @State private var viewModel: MatchDetailViewModel
    @State private var isPulsing = false

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
                        ProgressView("데이터 불러오는 중...")
                            .padding(.vertical, 24)
                    } else if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button("재시도") { Task { await viewModel.load() } }
                                .font(.subheadline)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        }
                    }

                    infoCard
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
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isPulsing ? 1.4 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                        .onAppear { isPulsing = true }
                    Text("LIVE")
                        .font(.caption).fontWeight(.bold).foregroundStyle(.red)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.red.opacity(0.15)).clipShape(Capsule())

                if let t = viewModel.lastPolledAt {
                    Text("업데이트 \(t, style: .relative) 전")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

        case .completed:
            Text("경기 종료")
                .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15)).clipShape(Capsule())

        case .unstarted:
            Text(match.startTime.formatted(
                .dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR"))
            ))
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1)).clipShape(Capsule())
        }
    }

    // MARK: - Game Series Picker

    private func gameSeriesPicker(detail: EventDetailInfo) -> some View {
        HStack(spacing: 6) {
            ForEach(detail.games.filter { $0.state != .unneeded }) { game in
                Button {
                    viewModel.selectedGameId = game.gameId
                } label: {
                    VStack(spacing: 3) {
                        Text("Game \(game.number)")
                            .font(.caption)
                            .fontWeight(viewModel.selectedGameId == game.gameId ? .bold : .regular)
                            .foregroundStyle(viewModel.selectedGameId == game.gameId ? .primary : .secondary)

                        Circle()
                            .fill(stateColor(game.state))
                            .frame(width: 5, height: 5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.selectedGameId == game.gameId
                            ? Color(.tertiarySystemGroupedBackground)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stateColor(_ state: GameInfoState) -> Color {
        switch state {
        case .completed:  return .blue
        case .inProgress: return .red
        default:          return Color.secondary.opacity(0.4)
        }
    }

    // MARK: - Ban Card

    private func banCard(game: GameInfo, blueBans: [String], redBans: [String]) -> some View {
        let blueTeam = teamFor(windowTeamId: game.blueTeamId)
        let redTeam  = teamFor(windowTeamId: game.redTeamId)

        return VStack(spacing: 0) {
            HStack {
                Text("밴")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            banRow(team: blueTeam, bans: blueBans, color: .blue)
            Divider().padding(.horizontal, 16)
            banRow(team: redTeam, bans: redBans, color: .red)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func banRow(team: Team?, bans: [String], color: Color) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                CachedAsyncImage(url: URL(string: team?.imageURL ?? ""))
                    .frame(width: 18, height: 18)
                Text(team?.code ?? "—")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .leading)
            }

            HStack(spacing: 6) {
                ForEach(bans, id: \.self) { champion in
                    ZStack(alignment: .topTrailing) {
                        ChampionImageView(championId: champion, size: 30)
                            .opacity(0.45)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                            .offset(x: 3, y: -3)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Team Stats Card

    private func teamStatsCard(window: GameWindow) -> some View {
        let blueTeam = teamFor(windowTeamId: window.blueTeamId)
        let redTeam  = teamFor(windowTeamId: window.redTeamId)

        return VStack(spacing: 0) {
            HStack {
                Text(blueTeam?.code ?? "Blue")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(redTeam?.code ?? "Red")
                    .font(.subheadline).fontWeight(.semibold)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            Divider().padding(.horizontal, 16)

            statRow(label: "킬",
                    left: "\(window.blueTeamStats.totalKills)",
                    right: "\(window.redTeamStats.totalKills)")
            statRow(label: "골드",
                    left: formatGold(window.blueTeamStats.totalGold),
                    right: formatGold(window.redTeamStats.totalGold))
            statRow(label: "타워",
                    left: "\(window.blueTeamStats.towers)",
                    right: "\(window.redTeamStats.towers)")
            statRow(label: "드래곤",
                    left: "\(window.blueTeamStats.dragons)",
                    right: "\(window.redTeamStats.dragons)")
            statRow(label: "바론",
                    left: "\(window.blueTeamStats.barons)",
                    right: "\(window.redTeamStats.barons)")
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statRow(label: String, left: String, right: String) -> some View {
        HStack {
            Text(left)
                .font(.subheadline).fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .center)
            Text(right)
                .font(.subheadline).fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - Player List Card

    private func playerListCard(window: GameWindow) -> some View {
        let blueTeam = teamFor(windowTeamId: window.blueTeamId)
        let redTeam  = teamFor(windowTeamId: window.redTeamId)

        return VStack(spacing: 0) {
            playerSection(team: blueTeam, sideLabel: "Blue", players: window.bluePlayers, color: .blue)
            Divider().padding(.horizontal, 16)
            playerSection(team: redTeam, sideLabel: "Red", players: window.redPlayers, color: .red)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerSection(team: Team?, sideLabel: String, players: [PlayerStats], color: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(team?.code ?? sideLabel)
                    .font(.subheadline).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)

            ForEach(players) { player in
                playerRow(player)
                if player.id != players.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private func playerRow(_ player: PlayerStats) -> some View {
        NavigationLink {
            PlayerDetailView(
                summonerName: player.summonerName,
                games: viewModel.eventDetail?.games.filter { $0.state.isPlayable } ?? [],
                gameWindows: viewModel.gameWindows,
                match: match
            )
        } label: {
            HStack(spacing: 8) {
                Text(roleLabel(player.role))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                ChampionImageView(championId: player.championId, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(player.championId)
                        .font(.caption).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(player.summonerName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if player.hasStats {
                    Text("\(player.kills)/\(player.deaths)/\(player.assists)")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(player.deaths == 0 ? .primary : .secondary)

                    Text(formatGold(player.totalGold))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    Text("\(player.creepScore)CS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Draft Waiting Card

    private var draftWaitingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("드래프트 대기 중...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - No Stats Card

    private var noStatsCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.secondary)
            Text("통계 데이터를 불러올 수 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(spacing: 0) {
            infoRow(label: "시작 시간", value: match.startTime.formatted(
                .dateTime.month().day().weekday().hour().minute()
                .locale(Locale(identifier: "ko_KR"))
            ))
            Divider().padding(.horizontal, 16)
            infoRow(label: "리그", value: match.league.name)
            if let live = liveMatch {
                Divider().padding(.horizontal, 16)
                infoRow(label: "마지막 업데이트", value: live.lastUpdated.formatted(
                    .relative(presentation: .numeric).locale(Locale(identifier: "ko_KR"))
                ))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - Helpers

    /// window의 esports 팀 ID로 match 팀을 반환.
    /// eventDetail의 esports ID → match 팀 코드 순으로 매칭.
    private func teamFor(windowTeamId: String) -> Team? {
        guard !windowTeamId.isEmpty else { return nil }
        if let detail = viewModel.eventDetail {
            if detail.teamAEsportsId == windowTeamId { return match.teamA }
            if detail.teamBEsportsId == windowTeamId { return match.teamB }
        }
        if match.teamA.id == windowTeamId || match.teamA.code == windowTeamId { return match.teamA }
        if match.teamB.id == windowTeamId || match.teamB.code == windowTeamId { return match.teamB }
        return nil
    }

    /// getSchedule에서 누락된 esports 팀 ID를 eventDetail 값으로 보완한 Team 반환.
    /// TeamDetailView.load()에서 fetchTeamRoster가 올바른 ID로 호출되도록 보장.
    private func resolvedTeam(_ team: Team) -> Team {
        guard let detail = viewModel.eventDetail else { return team }
        let esportsId = (team.code == match.teamA.code) ? detail.teamAEsportsId : detail.teamBEsportsId
        guard !esportsId.isEmpty, esportsId != team.id else { return team }
        return Team(id: esportsId, name: team.name, code: team.code, imageURL: team.imageURL)
    }

    private func roleLabel(_ role: String) -> String { RoleStyle.label(role) }

    private func formatGold(_ gold: Int) -> String {
        gold >= 1000 ? String(format: "%.1fk", Double(gold) / 1000) : "\(gold)"
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
