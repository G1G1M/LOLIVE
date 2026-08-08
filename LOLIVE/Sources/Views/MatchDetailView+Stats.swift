//
//  MatchDetailView+Stats.swift
//  LOLIVE
//
//  경기 상세 화면의 인게임 스탯 UI: 팀 스탯 카드, 선수 목록 카드, 통계 없음 카드.
//

import SwiftUI

extension MatchDetailView {

    // MARK: - Team Stats Card

    func blueTeamWon(_ window: GameWindow) -> Bool? {
        guard let game = viewModel.selectedGame, game.state == .completed else { return nil }
        // API가 승자 ID를 직접 제공하면 최우선 사용
        if let winnerId = game.winnerTeamId, !winnerId.isEmpty {
            return window.blueTeamId == winnerId
        }
        // fallback: 통계 계층 (inhibitors > towers > gold > kills)
        let b = window.blueTeamStats, r = window.redTeamStats
        if b.inhibitors != r.inhibitors { return b.inhibitors > r.inhibitors }
        if b.towers     != r.towers     { return b.towers     > r.towers     }
        if b.totalGold  != r.totalGold  { return b.totalGold  > r.totalGold  }
        if b.totalKills != r.totalKills { return b.totalKills > r.totalKills }
        return nil
    }

    func teamStatsCard(window: GameWindow) -> some View {
        let blueTeam  = teamFor(windowTeamId: window.blueTeamId)
        let redTeam   = teamFor(windowTeamId: window.redTeamId)
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

    func playerListCard(window: GameWindow) -> some View {
        let blueTeam = teamFor(windowTeamId: window.blueTeamId)
        let redTeam  = teamFor(windowTeamId: window.redTeamId)
        let blueWon  = blueTeamWon(window)

        return VStack(spacing: 0) {
            playerSection(team: blueTeam, sideLabel: "Blue", players: window.bluePlayers, color: .blue, isWinner: blueWon.map { $0 })
            Divider().padding(.horizontal, 16)
            playerSection(team: redTeam, sideLabel: "Red", players: window.redPlayers, color: .red, isWinner: blueWon.map { !$0 })
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerSection(team: Team?, sideLabel: String, players: [PlayerStats], color: Color, isWinner: Bool? = nil) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(team?.code ?? sideLabel)
                    .font(.subheadline).fontWeight(.semibold)
                if let isWinner {
                    Text(isWinner ? "WIN" : "LOSE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isWinner ? Color.blue : Color.red)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(isWinner ? Color.blue.opacity(0.15) : Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
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
                        .frame(width: 68, alignment: .trailing)
                        .lineLimit(1)

                    Text(formatGold(player.totalGold))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                        .lineLimit(1)

                    Text("\(player.creepScore)CS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func roleLabel(_ role: String) -> String { RoleStyle.label(role) }

    // MARK: - No Stats Card

    var noStatsCard: some View {
        EmptyStateView("통계 데이터를 불러올 수 없습니다", icon: "chart.bar.xaxis")
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 게임 상세(팀 스탯/선수 목록)를 아예 못 가져왔을 때(=selectedGameWindow가 nil)
    /// 화면이 통째로 비어 보이던 문제 대응 — "다시 시도" 버튼으로 재조회 기회를 준다.
    var statsUnavailableCard: some View {
        EmptyStateView(
            "경기 상세 정보를 불러올 수 없습니다", icon: "exclamationmark.triangle",
            actionTitle: "다시 시도"
        ) { Task { await viewModel.retryGameWindow() } }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
