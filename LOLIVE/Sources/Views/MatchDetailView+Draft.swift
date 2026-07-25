//
//  MatchDetailView+Draft.swift
//  LOLIVE
//
//  경기 상세 화면의 드래프트 관련 UI: 게임(세트) 선택 탭, 밴 카드, 드래프트 대기 카드.
//

import SwiftUI

extension MatchDetailView {

    // MARK: - Game Series Picker

    func gameSeriesPicker(detail: EventDetailInfo) -> some View {
        let games = detail.games.filter { $0.state != .unneeded }
        return HStack(spacing: 0) {
            ForEach(games) { game in
                let isSelected = viewModel.selectedGameId == game.gameId
                let isLive     = game.state == .inProgress

                Button {
                    viewModel.selectedGameId = game.gameId
                } label: {
                    VStack(spacing: 4) {
                        Text("G\(game.number)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : Color(.label))

                        if isLive {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 5, height: 5)
                                .scaleEffect(isPulsing ? 1.4 : 1.0)
                                .animation(
                                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                    value: isPulsing
                                )
                        } else if game.state == .unstarted {
                            Text("예정")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        } else {
                            if let code = gameWinnerCode(game: game, detail: detail) {
                                Text(code)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.accentColor)
                            } else {
                                Circle()
                                    .fill(isSelected ? Color.white.opacity(0.7) : Color.accentColor)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? Color.accentColor : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func gameWinnerCode(game: GameInfo, detail: EventDetailInfo) -> String? {
        guard let winnerId = game.winnerTeamId, !winnerId.isEmpty else { return nil }
        if winnerId == detail.teamAEsportsId { return match.teamA.code }
        if winnerId == detail.teamBEsportsId { return match.teamB.code }
        return teamFor(windowTeamId: winnerId)?.code
    }

    // MARK: - Ban Card

    func banCard(game: GameInfo, blueBans: [String], redBans: [String]) -> some View {
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

    // MARK: - Draft Waiting Card

    var draftWaitingCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text("경기 시작 전")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
