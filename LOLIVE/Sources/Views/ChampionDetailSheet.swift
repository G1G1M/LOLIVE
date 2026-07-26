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

struct ChampionDetailSheet: View {
    let stat: LeaguePlayerDetailViewModel.ChampionStat
    @Environment(\.dismiss) private var dismiss

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
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

    @ViewBuilder
    private var winRateChart: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 50% 기준선
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
                    .offset(y: geo.size.height * 0.5)

                // 누적 승률 꺾은선
                if cumulativePoints.count >= 2 {
                    Path { path in
                        for (i, pt) in cumulativePoints.enumerated() {
                            let x = xPos(i, total: cumulativePoints.count, width: geo.size.width)
                            let y = geo.size.height * (1.0 - pt.winRate)
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else       { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }

                // 게임별 승패 점 (승=파랑, 패=빨강)
                ForEach(Array(cumulativePoints.enumerated()), id: \.offset) { i, pt in
                    let x = xPos(i, total: cumulativePoints.count, width: geo.size.width)
                    let y = geo.size.height * (1.0 - pt.winRate)
                    Circle()
                        .fill(pt.won ? Color.blue : Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: x - 4, y: y - 4)
                }

                // Y축 레이블
                VStack {
                    Text("100%").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("50%").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("0%").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(height: geo.size.height)
            }
        }
    }

    /// index번째 점의 X 좌표. 전체 너비를 (total-1) 등분해 균등 배치.
    private func xPos(_ index: Int, total: Int, width: CGFloat) -> CGFloat {
        guard total > 1 else { return width / 2 }
        return CGFloat(index) / CGFloat(total - 1) * width
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
