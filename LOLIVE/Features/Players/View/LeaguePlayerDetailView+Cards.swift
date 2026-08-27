//
//  LeaguePlayerDetailView+Cards.swift
//  LOLIVE
//
//  선수 상세의 카드들 — 최근 폼, 챔피언풀, 최근경기.
//

import SwiftUI

extension LeaguePlayerDetailView {

    // MARK: - Recent Form Card

    var recentFormCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 폼")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(viewModel.recentResults.prefix(5)) { result in
                    VStack(spacing: 4) {
                        Text(result.won ? "W" : "L")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(result.won ? Color.blue : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(result.date.formatted(.dateTime
                            .month(.twoDigits).day()
                            .locale(Locale(identifier: "ko_KR"))))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()

                let wins = viewModel.recentResults.prefix(5).filter { $0.won }.count
                let total = min(viewModel.recentResults.count, 5)
                Text("\(wins)승 \(total - wins)패")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Champion Card

    var championCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("챔피언 풀")
                    .font(.headline)
                Spacer()
                Text("최근 \(viewModel.recentResults.count)경기 기준")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            HStack(spacing: 0) {
                Text("#").frame(width: 24, alignment: .center)
                Text("챔피언").frame(maxWidth: .infinity, alignment: .leading)
                Text("게임").frame(width: 38, alignment: .center)
                Text("승률").frame(width: 50, alignment: .center)
                Text("KDA").frame(width: 54, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider().padding(.horizontal, 16)

            ForEach(Array(viewModel.championStats.enumerated()), id: \.element.id) { idx, stat in
                Button {
                    selectedChampion = stat
                } label: {
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .center)

                        HStack(spacing: 8) {
                            ChampionImageView(championId: stat.championId, size: 30)
                            Text(stat.championId)
                                .font(.subheadline).fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(stat.games)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .center)

                        VStack(spacing: 3) {
                            Text(String(format: "%.0f%%", stat.winRate * 100))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(winRateColor(stat.winRate))
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                                .frame(height: 3)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(winRateColor(stat.winRate).opacity(0.8))
                                        .frame(width: 34 * stat.winRate)
                                }
                                .frame(width: 34)
                        }
                        .frame(width: 50, alignment: .center)

                        Text(String(format: "%.2f", stat.kda))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(kdaColor(stat.kda))
                            .frame(width: 54, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if idx < viewModel.championStats.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func winRateColor(_ rate: Double) -> Color {
        if rate >= 0.6 { return .blue }
        if rate < 0.4  { return .secondary }
        return Color(.label)
    }

    private func kdaColor(_ kda: Double) -> Color {
        if kda >= 4.0 { return .blue }
        if kda >= 2.0 { return Color(.label) }
        return .secondary
    }

    // MARK: - Recent Matches Card

    var recentMatchItems: [RecentMatchesCard.Item] {
        viewModel.recentResults.map { result in
            RecentMatchesCard.Item(id: result.id, match: result.match, opponent: result.opponent,
                                    myScore: result.myScore, oppScore: result.oppScore,
                                    won: result.won, date: result.date)
        }
    }
}
