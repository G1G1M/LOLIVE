//
//  ChampionDetailSheet.swift
//  LOLIVE
//
//  선수 상세 화면의 챔피언풀에서 챔피언을 탭했을 때 표시되는 시트.
//  해당 챔피언의 요약 스탯 · 승률 추이 차트 · 게임별 기록을 보여준다.
//
//  LeaguePlayerDetailView에서 분리됨 (리팩토링 Phase 2).
//

import SwiftUI
import Charts

struct ChampionDetailSheet: View {
    let stat: LeaguePlayerDetailViewModel.ChampionStat

    /// 승률 추이 차트용 누적 승률 데이터 포인트.
    /// n번째 게임까지의 누적 승률을 미리 계산해 차트를 그린다.
    private struct CumulativePoint: Identifiable {
        let id: Int
        let gameNumber: Int
        let winRate: Double
        let won: Bool
    }

    private var cumulativePoints: [CumulativePoint] {
        var wins = 0
        return stat.entries.enumerated().map { idx, entry in
            if entry.won { wins += 1 }
            return CumulativePoint(id: idx, gameNumber: idx + 1,
                                   winRate: Double(wins) / Double(idx + 1),
                                   won: entry.won)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        // 게임이 1개뿐이면 추이를 그릴 수 없으므로 차트 생략
                        if cumulativePoints.count >= 2 {
                            chartCard
                        }
                        gameListCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(stat.championId)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ChampionImageView(championId: stat.championId, size: 28)
                }
            }
            .sheetCloseButton()
        }
    }

    // MARK: - 요약 카드 (게임 수 / 승률 / KDA)

    private var summaryCard: some View {
        HStack(spacing: 0) {
            statCell("\(stat.games)", label: "게임")
            Divider().frame(height: 44)
            statCell(String(format: "%.0f%%", stat.winRate * 100),
                     label: "승률", color: winRateColor(stat.winRate))
            Divider().frame(height: 44)
            statCell(String(format: "%.2f", stat.kda),
                     label: "KDA", color: kdaColor(stat.kda))
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statCell(_ value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 승률 추이 차트

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("승률 추이")
                .font(.headline)

            winRateChart
                .frame(height: 200)

            resultDotsRow
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Swift Charts로 그리는 누적 승률 추이 — 부드러운 곡선 + 아래쪽 그라디언트 채움으로
    /// 주식 앱 차트처럼 보이게 하고, 게임별 승패는 점 색(승=파랑/패=빨강)으로 얹는다.
    private var winRateChart: some View {
        Chart {
            ForEach(cumulativePoints) { pt in
                AreaMark(
                    x: .value("게임", pt.gameNumber),
                    y: .value("승률", pt.winRate)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [Color.blue.opacity(0.22), Color.blue.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                )

                LineMark(
                    x: .value("게임", pt.gameNumber),
                    y: .value("승률", pt.winRate)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))

                PointMark(
                    x: .value("게임", pt.gameNumber),
                    y: .value("승률", pt.winRate)
                )
                .foregroundStyle(pt.won ? Color.blue : Color.red)
                .symbolSize(30)
            }

            // 50% 기준선
            RuleMark(y: .value("기준", 0.5))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v * 100))%")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
    }

    /// 차트 아래 W/L 결과 뱃지 가로 스크롤 행.
    private var resultDotsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(stat.entries.enumerated()), id: \.offset) { idx, entry in
                    VStack(spacing: 2) {
                        Text(entry.won ? "W" : "L")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(entry.won ? Color.blue : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text("\(idx + 1)")
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - 게임별 기록 리스트

    private var gameListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("게임 기록")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().padding(.horizontal, 16)
            ForEach(Array(stat.entries.enumerated()), id: \.offset) { idx, entry in
                HStack(spacing: 12) {
                    Text(entry.won ? "W" : "L")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(entry.won ? Color.blue : Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    Text("게임 \(idx + 1)")
                        .font(.subheadline)

                    Spacer()

                    if let d = entry.date {
                        Text(d.formatted(.dateTime.month(.abbreviated).day()
                            .locale(Locale(identifier: "ko_KR"))))
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }

                    Text("\(entry.kills)/\(entry.deaths)/\(entry.assists)")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if idx < stat.entries.count - 1 {
                    Divider().padding(.leading, 50)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 색상 헬퍼

    /// 승률 60% 이상 = 파랑(좋음), 40% 미만 = 회색(낮음)
    private func winRateColor(_ rate: Double) -> Color {
        if rate >= 0.6 { return .blue }
        if rate < 0.4  { return .secondary }
        return Color(.label)
    }

    /// KDA 4.0 이상 = 파랑(우수), 2.0 미만 = 회색(낮음)
    private func kdaColor(_ kda: Double) -> Color {
        if kda >= 4.0 { return .blue }
        if kda >= 2.0 { return Color(.label) }
        return .secondary
    }
}
