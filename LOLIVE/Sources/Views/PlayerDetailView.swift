//
//  PlayerDetailView.swift
//  LOLIVE
//

import SwiftUI

struct PlayerDetailView: View {
    let summonerName: String
    let games: [GameInfo]
    let gameWindows: [String: GameWindow]
    let match: Match

    private struct GameStat: Identifiable {
        var id: Int { gameNumber }
        let gameNumber: Int
        let championId: String
        let kills: Int
        let deaths: Int
        let assists: Int
        let totalGold: Int
        let creepScore: Int
    }

    private var allStats: [GameStat] {
        games.filter { $0.state.isPlayable }.compactMap { game in
            guard let window = gameWindows[game.gameId] else { return nil }
            let allPlayers = window.bluePlayers + window.redPlayers
            guard let p = allPlayers.first(where: { $0.summonerName == summonerName }) else { return nil }
            return GameStat(
                gameNumber: game.number,
                championId: p.championId,
                kills: p.kills,
                deaths: p.deaths,
                assists: p.assists,
                totalGold: p.totalGold,
                creepScore: p.creepScore
            )
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    matchInfoCard
                    if !allStats.isEmpty {
                        statsCard
                    } else {
                        noDataCard
                    }
                }
                .padding()
            }
        }
        .navigationTitle(summonerName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Match Info

    private var matchInfoCard: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: match.teamA.imageURL ?? ""))
                .frame(width: 40, height: 40)
            VStack(spacing: 2) {
                Text("\(match.teamA.code) vs \(match.teamB.code)")
                    .font(.subheadline).fontWeight(.semibold)
                Text(match.league.name)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(match.scoreA) - \(match.scoreB)")
                .font(.headline).fontWeight(.bold)
            CachedAsyncImage(url: URL(string: match.teamB.imageURL ?? ""))
                .frame(width: 40, height: 40)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("게임")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Text("챔피언")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("KDA")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .center)
                Text("골드")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                Text("CS")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider().padding(.horizontal, 16)

            ForEach(allStats) { stat in
                HStack {
                    Text("Game \(stat.gameNumber)")
                        .font(.caption).fontWeight(.medium)
                        .frame(width: 52, alignment: .leading)
                    Text(stat.championId)
                        .font(.caption).fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(stat.kills)/\(stat.deaths)/\(stat.assists)")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(stat.deaths == 0 ? .primary : .secondary)
                        .frame(width: 70, alignment: .center)
                    Text(formatGold(stat.totalGold))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Text("\(stat.creepScore)CS")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if stat.id != allStats.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - No Data

    private var noDataCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.secondary)
            Text("통계 데이터를 불러올 수 없습니다")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func formatGold(_ gold: Int) -> String {
        gold >= 1000 ? String(format: "%.1fk", Double(gold) / 1000) : "\(gold)"
    }
}
