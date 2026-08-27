//
//  TeamDetailView+Stats.swift
//  LOLIVE
//
//  팀 상세 "스탯" 탭의 요약 카드. 탭하면 TeamStatsDetailSheet로 드릴다운한다.
//

import SwiftUI

extension TeamDetailView {

    func teamStatsCard(_ stats: TeamSeasonStats) -> some View {
        let winPct = Int((stats.winRate * 100).rounded())
        let winColor: Color = stats.winRate >= 0.6 ? .blue : stats.winRate >= 0.5 ? .green : .orange
        let gdColor: Color = stats.goldDiffAt15 > 0 ? .blue : stats.goldDiffAt15 < 0 ? .red : .secondary
        let gdText = (stats.goldDiffAt15 > 0 ? "+" : "") + String(format: "%.0f", stats.goldDiffAt15)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("시즌 스탯")
                    .font(.headline)
                Spacer()
                Text("\(stats.games)경기")
                    .font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("\(winPct)%")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(winColor)
                    Text("승률")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(stats.wins)승 \(stats.losses)패")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(.tertiarySystemFill))
                        RoundedRectangle(cornerRadius: 3).fill(winColor.opacity(0.7))
                            .frame(width: max(6, geo.size.width * stats.winRate))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)

            Divider().padding(.horizontal, 16)

            HStack(spacing: 0) {
                teamStatColumn(value: String(format: "%.0f분", stats.avgGameMinutes), label: "평균 게임시간")
                Divider().frame(height: 44)
                teamStatColumn(value: gdText, label: "15분 골드차", color: gdColor)
            }
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 16)

            HStack(spacing: 0) {
                teamStatColumn(value: "\(Int((stats.firstBloodRate * 100).rounded()))%", label: "퍼스트 블러드")
                Divider().frame(height: 44)
                teamStatColumn(value: "\(Int((stats.dragonRate * 100).rounded()))%", label: "드래곤 획득률")
                Divider().frame(height: 44)
                teamStatColumn(value: "\(Int((stats.baronRate * 100).rounded()))%", label: "바론 획득률")
            }
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { showStatsDetail = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("시즌 스탯 상세 보기")
    }

    private func teamStatColumn(value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.body, design: .rounded)).fontWeight(.bold)
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
