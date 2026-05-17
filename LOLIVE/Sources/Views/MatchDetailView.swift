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
                    } else if let detail = viewModel.eventDetail {
                        if detail.games.filter({ $0.state != .unneeded }).count > 1 {
                            gameSeriesPicker(detail: detail)
                        }

                        if let window = viewModel.selectedGameWindow {
                            let gameIsLive = viewModel.selectedGame?.state == .inProgress
                            if window.hasLiveStats || gameIsLive {
                                teamStatsCard(window: window, match: match)
                                playerListCard(window: window, match: match)
                            } else {
                                playerListCard(window: window, match: match)
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
        .navigationDestination(for: PlayerStats.self) { player in
            PlayerDetailView(
                summonerName: player.summonerName,
                games: viewModel.eventDetail?.games.filter { $0.state.isPlayable } ?? [],
                gameWindows: viewModel.gameWindows,
                match: match
            )
        }
        .navigationDestination(for: Team.self) { team in
            TeamDetailView(team: team, league: match.league)
        }
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
                teamColumn(team: match.teamA, isWinner: match.scoreA > match.scoreB)
                scoreColumn
                teamColumn(team: match.teamB, isWinner: match.scoreB > match.scoreA)
            }
        }
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func teamColumn(team: Team, isWinner: Bool) -> some View {
        NavigationLink(value: team) {
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

    // MARK: - Team Stats Card

    private func teamStatsCard(window: GameWindow, match: Match) -> some View {
        let blueTeam = teamFor(id: window.blueTeamId, match: match)
        let redTeam  = teamFor(id: window.redTeamId,  match: match)

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

    private func playerListCard(window: GameWindow, match: Match) -> some View {
        let blueTeam = teamFor(id: window.blueTeamId, match: match)
        let redTeam  = teamFor(id: window.redTeamId,  match: match)

        return VStack(spacing: 0) {
            playerSection(
                title: blueTeam?.code ?? "Blue Side",
                players: window.bluePlayers,
                color: .blue
            )
            Divider().padding(.horizontal, 16)
            playerSection(
                title: redTeam?.code ?? "Red Side",
                players: window.redPlayers,
                color: .red
            )
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerSection(title: String, players: [PlayerStats], color: Color) -> some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
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
        NavigationLink(value: player) {
            HStack(spacing: 8) {
                Text(roleLabel(player.role))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

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

    private func teamFor(id: String, match: Match) -> Team? {
        if match.teamA.id == id { return match.teamA }
        if match.teamB.id == id { return match.teamB }
        return nil
    }

    private func roleLabel(_ role: String) -> String {
        switch role.lowercased() {
        case "top":     return "TOP"
        case "jungle":  return "JGL"
        case "mid":     return "MID"
        case "bottom":  return "BOT"
        case "support": return "SUP"
        default:        return role.uppercased()
        }
    }

    private func formatGold(_ gold: Int) -> String {
        gold >= 1000 ? String(format: "%.1fk", Double(gold) / 1000) : "\(gold)"
    }
}

#Preview {
    let league = League(id: "1", name: "LCK", region: "Korea", imageURL: nil)
    let t1  = Team(id: "t1",  name: "T1",    code: "T1",  imageURL: nil)
    let gen = Team(id: "gen", name: "Gen.G", code: "GEN", imageURL: nil)
    let match = Match(id: "m1", league: league, teamA: t1, teamB: gen,
                      scoreA: 2, scoreB: 1, startTime: Date(), state: .completed)

    NavigationStack {
        MatchDetailView(match: match)
    }
    .preferredColorScheme(.dark)
}
