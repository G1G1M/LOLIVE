//
//  TeamStatsDetailSheet.swift
//  LOLIVE
//
//  팀 상세의 "스탯" 탭 카드를 탭했을 때 표시되는 시트. TeamSeasonStats에는 있지만
//  요약 카드에는 자리가 없던 나머지 Oracle's Elixir 필드를 카테고리별로 보여준다.
//  비율(0~100%) 값은 한눈에 비교되도록 막대를 같이 그리고, 카테고리마다 다른 톤 컬러로
//  구분해 숫자만 나열된 표처럼 보이지 않게 했다. 공용 카드/행 컴포넌트는
//  StatDetailComponents.swift(선수 스탯 상세와 공유).
//

import SwiftUI

struct TeamStatsDetailSheet: View {
    let teamName: String
    let stats: TeamSeasonStats

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
            .sheetCloseButton()
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
        StatDetailCard(icon: "bolt.fill", tint: .orange, title: "전투") {
            StatDetailRow(label: "킬 / 데스", value: "\(stats.kills) / \(stats.deaths)")
            StatDetailRow(label: "킬/데스 비율", value: String(format: "%.2f", stats.killDeathRatio),
                          valueColor: stats.killDeathRatio >= 1 ? .blue : .red)
            StatDetailRow(label: "분당 합산 킬", value: String(format: "%.2f", stats.combinedKillsPerMinute))
            StatRateRow(label: "퍼스트 블러드", value: stats.firstBloodRate, tint: .orange)
            StatRateRow(label: "첫 타워 획득", value: stats.firstTowerRate, tint: .orange)
            StatRateRow(label: "3타워 선점", value: stats.firstToThreeTowersRate, tint: .orange)
            StatDetailRow(label: "게임당 타워 골드판", value: String(format: "%.1f개", stats.platesPerGame))
        }
    }

    // MARK: - 오브젝트

    private var objectiveCard: some View {
        StatDetailCard(icon: "shield.lefthalf.filled", tint: .purple, title: "오브젝트") {
            StatRateRow(label: "첫 드래곤", value: stats.firstDragonRate, tint: .purple)
            StatRateRow(label: "드래곤 획득률", value: stats.dragonRate, tint: .purple)
            if let elder = stats.elderDragonRate {
                StatRateRow(label: "장로 드래곤", value: elder, tint: .purple)
            } else {
                StatDetailRow(label: "장로 드래곤", value: "-", valueColor: .secondary)
            }
            StatRateRow(label: "전령 획득률", value: stats.heraldRate, tint: .purple)
            StatRateRow(label: "공허 유충 획득률", value: stats.voidGrubsRate, tint: .purple)
            StatRateRow(label: "첫 바론", value: stats.firstBaronRate, tint: .purple)
            StatRateRow(label: "바론 획득률", value: stats.baronRate, tint: .purple)
        }
    }

    // MARK: - 골드 · 라인전

    private var goldLaningCard: some View {
        let gprText = (stats.goldPercentRating > 0 ? "+" : "") + String(format: "%.2f", stats.goldPercentRating)
        let gspdText = (stats.goldSpentPercentDiff > 0 ? "+" : "") + String(format: "%.1f%%", stats.goldSpentPercentDiff * 100)

        return StatDetailCard(icon: "banknote.fill", tint: .green, title: "골드 · 라인전") {
            StatDetailRow(label: "골드 점유 지수(50 기준)", value: gprText, valueColor: statRatingColor(stats.goldPercentRating))
            StatDetailRow(label: "골드 소비 격차", value: gspdText, valueColor: statRatingColor(stats.goldSpentPercentDiff))
            StatDetailRow(label: "초반 게임 지수", value: String(format: "%.1f", stats.earlyGameRating),
                          valueColor: statRatingColor(stats.earlyGameRating - 50))
            StatDetailRow(label: "중후반 게임 지수", value: String(format: "%.1f", stats.midLateRating),
                          valueColor: statRatingColor(stats.midLateRating))
            StatRateRow(label: "라인전 CS 점유율", value: stats.laneCsShare, tint: .green)
            StatRateRow(label: "정글 CS 점유율", value: stats.jungleCsShare, tint: .green)
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
