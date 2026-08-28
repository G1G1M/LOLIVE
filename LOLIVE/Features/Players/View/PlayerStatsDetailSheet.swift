//
//  PlayerStatsDetailSheet.swift
//  LOLIVE
//
//  선수 상세의 "통계" 탭 카드를 탭했을 때 표시되는 시트. PlayerOEStats(Oracle's Elixir)에는
//  있지만 요약 카드엔 자리가 없던 킬관여율·데미지/골드 기여도·라인전 격차·시야 지표를
//  카테고리별로 보여준다. TeamStatsDetailSheet와 같은 공용 컴포넌트(StatDetailComponents.swift) 사용.
//

import SwiftUI

struct PlayerStatsDetailSheet: View {
    let playerName: String
    let stats: PlayerOEStats

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
                        laningCard
                        damageGoldCard
                        visionCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(playerName)
            .navigationBarTitleDisplayMode(.inline)
            .sheetCloseButton()
        }
    }

    // MARK: - 요약 히어로

    private var heroCard: some View {
        HStack(spacing: 18) {
            WinRateRing(winRate: stats.winRate, color: winColor)
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text("KDA \(String(format: "%.2f", stats.kda))")
                    .font(.title3).fontWeight(.bold)
                Text("\(stats.games)경기 · \(stats.kills)/\(stats.deaths)/\(stats.assists)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill").font(.caption2).fontWeight(.bold)
                    Text("킬관여율 \(Int((stats.killParticipation * 100).rounded()))%")
                        .font(.caption).fontWeight(.semibold)
                }
                .foregroundStyle(.orange)
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
        StatDetailCard(icon: "bolt.fill", tint: .orange, title: "전투") {
            StatDetailRow(label: "킬 / 데스 / 어시", value: "\(stats.kills) / \(stats.deaths) / \(stats.assists)")
            StatDetailRow(label: "KDA", value: String(format: "%.2f", stats.kda),
                          valueColor: stats.kda >= 4 ? .blue : stats.kda >= 2 ? .primary : .red)
            StatRateRow(label: "킬 관여율", value: stats.killParticipation, tint: .orange)
            StatRateRow(label: "팀 킬 중 비중", value: stats.killShare, tint: .orange)
            StatRateRow(label: "팀 데스 중 비중", value: stats.deathShare, tint: .orange)
            StatRateRow(label: "퍼스트 블러드 관여", value: stats.firstBloodRate, tint: .orange)
            StatDetailRow(label: "오브젝트 스틸", value: "\(stats.steals)회")
        }
    }

    // MARK: - 라인전

    private var laningCard: some View {
        let gd10Text = stats.goldDiffAt10.map { ($0 > 0 ? "+" : "") + String(format: "%.0f", $0) } ?? "-"
        let xpd10Text = stats.xpDiffAt10.map { ($0 > 0 ? "+" : "") + String(format: "%.0f", $0) } ?? "-"
        let csd10Text = stats.csDiffAt10.map { ($0 > 0 ? "+" : "") + String(format: "%.1f", $0) } ?? "-"

        return StatDetailCard(icon: "arrow.left.arrow.right", tint: .teal, title: "라인전") {
            StatDetailRow(label: "10분 골드 격차", value: gd10Text,
                          valueColor: stats.goldDiffAt10.map(statRatingColor) ?? .secondary)
            StatDetailRow(label: "10분 경험치 격차", value: xpd10Text,
                          valueColor: stats.xpDiffAt10.map(statRatingColor) ?? .secondary)
            StatDetailRow(label: "10분 CS 격차", value: csd10Text,
                          valueColor: stats.csDiffAt10.map(statRatingColor) ?? .secondary)
            StatDetailRow(label: "분당 CS", value: String(format: "%.1f", stats.csPerMin))
            StatRateRow(label: "15분 CS 점유율", value: stats.csShareAt15, tint: .teal)
        }
    }

    // MARK: - 딜 · 골드

    private var damageGoldCard: some View {
        StatDetailCard(icon: "flame.fill", tint: .pink, title: "딜 · 골드") {
            StatDetailRow(label: "분당 데미지", value: String(format: "%.0f", stats.damagePerMin))
            StatRateRow(label: "팀 데미지 중 비중", value: stats.damageShare, tint: .pink)
            StatRateRow(label: "15분 데미지 비중", value: stats.damageShareAt15, tint: .pink)
            StatDetailRow(label: "게임당 총 데미지", value: String(format: "%.0f", stats.totalDamagePerGame))
            StatDetailRow(label: "분당 획득 골드", value: String(format: "%.0f", stats.earnedGoldPerMin))
            StatRateRow(label: "팀 골드 중 비중", value: stats.goldShare, tint: .pink)
        }
    }

    // MARK: - 시야

    private var visionCard: some View {
        StatDetailCard(icon: "eye.fill", tint: .indigo, title: "시야") {
            StatDetailRow(label: "분당 와드 설치", value: String(format: "%.2f", stats.wardsPerMinute))
            StatDetailRow(label: "분당 제어 와드", value: String(format: "%.2f", stats.controlWardsPerMinute))
            StatDetailRow(label: "분당 와드 제거", value: String(format: "%.2f", stats.wardsClearedPerMinute))
        }
    }
}
