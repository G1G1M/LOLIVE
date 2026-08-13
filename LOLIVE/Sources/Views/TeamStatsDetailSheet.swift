//
//  TeamStatsDetailSheet.swift
//  LOLIVE
//
//  팀 상세의 "스탯" 탭 카드를 탭했을 때 표시되는 시트. TeamSeasonStats에는 있지만
//  요약 카드에는 자리가 없던 나머지 Oracle's Elixir 필드를 카테고리별로 보여준다.
//

import SwiftUI

struct TeamStatsDetailSheet: View {
    let teamName: String
    let stats: TeamSeasonStats
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        combatCard
                        objectiveCard
                        goldLaningCard
                        visionCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(teamName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(teamName).font(.headline)
                        Text("\(stats.games)경기 \(stats.wins)승 \(stats.losses)패 · 평균 \(String(format: "%.0f", stats.avgGameMinutes))분")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    // MARK: - 전투

    private var combatCard: some View {
        statCard(title: "전투") {
            statGrid([
                ("\(stats.kills)/\(stats.deaths)", "킬/데스"),
                (String(format: "%.2f", stats.killDeathRatio), "킬/데스 비율"),
                (String(format: "%.2f", stats.combinedKillsPerMinute), "분당 합산 킬"),
                (pct(stats.firstBloodRate), "퍼스트 블러드"),
                (pct(stats.firstTowerRate), "첫 타워 획득"),
                (pct(stats.firstToThreeTowersRate), "3타워 선점"),
                (String(format: "%.1f개", stats.platesPerGame), "게임당 타워 골드판"),
            ])
        }
    }

    // MARK: - 오브젝트

    private var objectiveCard: some View {
        statCard(title: "오브젝트") {
            statGrid([
                (pct(stats.firstDragonRate), "첫 드래곤"),
                (pct(stats.dragonRate), "드래곤 획득률"),
                (stats.elderDragonRate.map(pct) ?? "-", "장로 드래곤"),
                (pct(stats.heraldRate), "전령 획득률"),
                (pct(stats.voidGrubsRate), "공허 유충 획득률"),
                (pct(stats.firstBaronRate), "첫 바론"),
                (pct(stats.baronRate), "바론 획득률"),
            ])
        }
    }

    // MARK: - 골드 · 라인전

    private var goldLaningCard: some View {
        let gd15Text = (stats.goldDiffAt15 > 0 ? "+" : "") + String(format: "%.0f", stats.goldDiffAt15)
        let gd15Color: Color = stats.goldDiffAt15 > 0 ? .blue : stats.goldDiffAt15 < 0 ? .red : .secondary
        let gprText = (stats.goldPercentRating > 0 ? "+" : "") + String(format: "%.2f", stats.goldPercentRating)
        let gspdText = (stats.goldSpentPercentDiff > 0 ? "+" : "") + String(format: "%.1f%%", stats.goldSpentPercentDiff * 100)

        return statCard(title: "골드 · 라인전") {
            statGrid([
                (gd15Text, "15분 골드 격차", gd15Color),
                (gprText, "골드 점유 지수(50 기준)", ratingColor(stats.goldPercentRating)),
                (gspdText, "골드 소비 격차", ratingColor(stats.goldSpentPercentDiff)),
                (String(format: "%.1f", stats.earlyGameRating), "초반 게임 지수", ratingColor(stats.earlyGameRating - 50)),
                (String(format: "%.1f", stats.midLateRating), "중후반 게임 지수", ratingColor(stats.midLateRating)),
                (pct(stats.laneCsShare), "라인전 CS 점유율", Color.primary),
                (pct(stats.jungleCsShare), "정글 CS 점유율", Color.primary),
            ])
        }
    }

    // MARK: - 시야

    private var visionCard: some View {
        statCard(title: "시야") {
            statGrid([
                (String(format: "%.2f", stats.wardsPerMinute), "분당 와드 설치"),
                (String(format: "%.2f", stats.controlWardsPerMinute), "분당 제어 와드"),
                (String(format: "%.2f", stats.wardsClearedPerMinute), "분당 와드 제거"),
            ])
        }
    }

    // MARK: - 공통 컴포넌트

    private func statCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private func statGrid(_ items: [(String, String, Color)]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                statCell(value: item.0, label: item.1, color: item.2)
            }
        }
    }

    private func statGrid(_ items: [(String, String)]) -> some View {
        statGrid(items.map { ($0.0, $0.1, Color.primary) })
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.body, design: .rounded)).fontWeight(.bold)
                .foregroundStyle(color)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// 0을 기준으로 양수=파랑(우세)/음수=빨강(열세)로 색칠하는 공용 규칙.
    private func ratingColor(_ value: Double) -> Color {
        value > 0 ? .blue : value < 0 ? .red : .secondary
    }
}
