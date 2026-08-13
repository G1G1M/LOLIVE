//
//  TeamStatsDetailSheet.swift
//  LOLIVE
//
//  팀 상세의 "스탯" 탭 카드를 탭했을 때 표시되는 시트. TeamSeasonStats에는 있지만
//  요약 카드에는 자리가 없던 나머지 Oracle's Elixir 필드를 카테고리별로 보여준다.
//  비율(0~100%) 값은 한눈에 비교되도록 막대를 같이 그리고, 카테고리마다 다른 톤 컬러로
//  구분해 숫자만 나열된 표처럼 보이지 않게 했다.
//

import SwiftUI

struct TeamStatsDetailSheet: View {
    let teamName: String
    let stats: TeamSeasonStats
    @Environment(\.dismiss) private var dismiss

    private var winColor: Color {
        stats.winRate >= 0.6 ? .blue : stats.winRate >= 0.5 ? .green : .orange
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        heroCard
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    // MARK: - 요약 히어로

    private var heroCard: some View {
        let gdColor: Color = stats.goldDiffAt15 > 0 ? .blue : stats.goldDiffAt15 < 0 ? .red : .secondary
        let gdText = (stats.goldDiffAt15 > 0 ? "+" : "") + String(format: "%.0f", stats.goldDiffAt15)

        return HStack(spacing: 18) {
            WinRateRing(winRate: stats.winRate, color: winColor)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(stats.wins)승 \(stats.losses)패")
                    .font(.title3).fontWeight(.bold)
                Text("\(stats.games)경기 · 평균 \(String(format: "%.0f", stats.avgGameMinutes))분")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: stats.goldDiffAt15 >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2).fontWeight(.bold)
                    Text("15분 골드 \(gdText)")
                        .font(.caption).fontWeight(.semibold)
                }
                .foregroundStyle(gdColor)
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 전투

    private var combatCard: some View {
        statCard(icon: "bolt.fill", tint: .orange, title: "전투") {
            statRow(label: "킬 / 데스", value: "\(stats.kills) / \(stats.deaths)")
            statRow(label: "킬/데스 비율", value: String(format: "%.2f", stats.killDeathRatio),
                    valueColor: stats.killDeathRatio >= 1 ? .blue : .red)
            statRow(label: "분당 합산 킬", value: String(format: "%.2f", stats.combinedKillsPerMinute))
            rateRow(label: "퍼스트 블러드", value: stats.firstBloodRate, tint: .orange)
            rateRow(label: "첫 타워 획득", value: stats.firstTowerRate, tint: .orange)
            rateRow(label: "3타워 선점", value: stats.firstToThreeTowersRate, tint: .orange)
            statRow(label: "게임당 타워 골드판", value: String(format: "%.1f개", stats.platesPerGame))
        }
    }

    // MARK: - 오브젝트

    private var objectiveCard: some View {
        statCard(icon: "shield.lefthalf.filled", tint: .purple, title: "오브젝트") {
            rateRow(label: "첫 드래곤", value: stats.firstDragonRate, tint: .purple)
            rateRow(label: "드래곤 획득률", value: stats.dragonRate, tint: .purple)
            if let elder = stats.elderDragonRate {
                rateRow(label: "장로 드래곤", value: elder, tint: .purple)
            } else {
                statRow(label: "장로 드래곤", value: "-", valueColor: .secondary)
            }
            rateRow(label: "전령 획득률", value: stats.heraldRate, tint: .purple)
            rateRow(label: "공허 유충 획득률", value: stats.voidGrubsRate, tint: .purple)
            rateRow(label: "첫 바론", value: stats.firstBaronRate, tint: .purple)
            rateRow(label: "바론 획득률", value: stats.baronRate, tint: .purple)
        }
    }

    // MARK: - 골드 · 라인전

    private var goldLaningCard: some View {
        let gprText = (stats.goldPercentRating > 0 ? "+" : "") + String(format: "%.2f", stats.goldPercentRating)
        let gspdText = (stats.goldSpentPercentDiff > 0 ? "+" : "") + String(format: "%.1f%%", stats.goldSpentPercentDiff * 100)

        return statCard(icon: "banknote.fill", tint: .green, title: "골드 · 라인전") {
            statRow(label: "골드 점유 지수(50 기준)", value: gprText, valueColor: ratingColor(stats.goldPercentRating))
            statRow(label: "골드 소비 격차", value: gspdText, valueColor: ratingColor(stats.goldSpentPercentDiff))
            statRow(label: "초반 게임 지수", value: String(format: "%.1f", stats.earlyGameRating),
                    valueColor: ratingColor(stats.earlyGameRating - 50))
            statRow(label: "중후반 게임 지수", value: String(format: "%.1f", stats.midLateRating),
                    valueColor: ratingColor(stats.midLateRating))
            rateRow(label: "라인전 CS 점유율", value: stats.laneCsShare, tint: .green)
            rateRow(label: "정글 CS 점유율", value: stats.jungleCsShare, tint: .green)
        }
    }

    // MARK: - 시야

    private var visionCard: some View {
        statCard(icon: "eye.fill", tint: .indigo, title: "시야") {
            statRow(label: "분당 와드 설치", value: String(format: "%.2f", stats.wardsPerMinute))
            statRow(label: "분당 제어 와드", value: String(format: "%.2f", stats.controlWardsPerMinute))
            statRow(label: "분당 와드 제거", value: String(format: "%.2f", stats.wardsClearedPerMinute))
        }
    }

    // MARK: - 공통 컴포넌트

    private func statCard(icon: String, tint: Color, title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 28, height: 28)

                Text(title).font(.headline)
            }

            VStack(spacing: 14) { rows() }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 값 하나(레이블 + 우측 숫자)만 있는 일반 행.
    private func statRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
    }

    /// 0~100% 비율 행 — 숫자만으로는 비교가 어려워서 막대를 같이 그린다.
    private func rateRow(label: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(pct(value))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(value >= 0.5 ? tint : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(tint.opacity(0.8))
                        .frame(width: max(4, geo.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 5)
        }
    }

    private func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// 0을 기준으로 양수=파랑(우세)/음수=빨강(열세)로 색칠하는 공용 규칙.
    private func ratingColor(_ value: Double) -> Color {
        value > 0 ? .blue : value < 0 ? .red : .secondary
    }
}

/// 히어로 카드의 승률 도넛. 원형 트랙 위에 승률만큼 색을 채운다.
private struct WinRateRing: View {
    let winRate: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0.02, min(winRate, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((winRate * 100).rounded()))%")
                .font(.system(.callout, design: .rounded)).fontWeight(.bold)
                .minimumScaleFactor(0.7).lineLimit(1)
        }
    }
}
