//
//  SeasonStatsView.swift
//  LOLIVE
//

import SwiftUI

struct SeasonStatsView: View {
    let stats: PlayerSeasonStats?
    let isLoading: Bool
    /// nil이 아니면 카드에 "더보기" chevron이 붙고 탭하면 이 클로저 호출 (상세 시트 오픈용).
    var onTapDetail: (() -> Void)? = nil

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.9)
                    Text("시즌 스탯 불러오는 중...")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if let stats {
                statsCard(stats)
            } else {
                EmptyStateView("시즌 스탯 없음", icon: "chart.bar.xaxis")
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Stats Card

    private func statsCard(_ stats: PlayerSeasonStats) -> some View {
        let winPct  = Int((stats.winRate * 100).rounded())
        let wins    = Int((stats.winRate * Double(stats.games)).rounded())
        let losses  = stats.games - wins
        let winColor: Color = stats.winRate >= 0.6 ? .blue
                            : stats.winRate >= 0.5 ? .green : .orange
        let kdaColor: Color = stats.kdaRatio >= 4.0 ? .blue
                            : stats.kdaRatio >= 2.0 ? .primary : .red

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("시즌 스탯")
                    .font(.headline)
                Spacer()
                Text("\(stats.games)경기")
                    .font(.caption).foregroundStyle(.secondary)
                if onTapDetail != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.tertiary)
                }
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
                    Text("\(wins)승 \(losses)패")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.tertiarySystemFill))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(winColor.opacity(0.7))
                            .frame(width: max(6, geo.size.width * stats.winRate))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)

            Divider().padding(.horizontal, 16)

            HStack(spacing: 0) {
                statColumn(value: String(format: "%.2f", stats.kdaRatio),
                           label: "KDA", color: kdaColor)
                Divider().frame(height: 44)
                statColumn(value: "\(winPct)%", label: "승률")
                Divider().frame(height: 44)
                statColumn(value: String(format: "%.1f", stats.avgCSPerMin),
                           label: "CS/분")
            }
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 16)

            HStack(spacing: 0) {
                statColumn(value: String(format: "%.1f", stats.avgKills),   label: "킬")
                Divider().frame(height: 44)
                statColumn(value: String(format: "%.1f", stats.avgDeaths),  label: "데스")
                Divider().frame(height: 44)
                statColumn(value: String(format: "%.1f", stats.avgAssists), label: "어시스트")
            }
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 16)

            kdaProportionBar(stats)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onTapDetail?() }
        .accessibilityAddTraits(onTapDetail != nil ? .isButton : [])
    }

    private func kdaProportionBar(_ stats: PlayerSeasonStats) -> some View {
        let k = stats.avgKills
        let d = stats.avgDeaths
        let a = stats.avgAssists
        let total = k + d + a
        guard total > 0 else { return AnyView(EmptyView()) }
        let kRatio = k / total
        let dRatio = d / total

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: max(4, geo.size.width * kRatio))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.8))
                        .frame(width: max(4, geo.size.width * dRatio))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.8))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                legendDot(color: .blue, label: "킬", value: String(format: "%.1f", k))
                legendDot(color: .red, label: "데스", value: String(format: "%.1f", d))
                legendDot(color: .green, label: "어시", value: String(format: "%.1f", a))
            }
            .font(.caption2).foregroundStyle(.secondary)
        })
    }

    private func legendDot(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.8)).frame(width: 7, height: 7)
            Text("\(label) \(value)")
        }
    }

    private func statColumn(value: String, label: String,
                            color: Color = .primary) -> some View {
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
