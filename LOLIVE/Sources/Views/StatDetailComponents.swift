//
//  StatDetailComponents.swift
//  LOLIVE
//
//  팀/선수 스탯 상세 시트(TeamStatsDetailSheet, PlayerStatsDetailSheet)가 공유하는
//  카드·행·도넛 링 컴포넌트. 원래 TeamStatsDetailSheet 안에 있던 걸 선수 쪽에도
//  똑같이 필요해져서 공용으로 뽑았다.
//

import SwiftUI

/// 카테고리 카드 — 아이콘 배지 + 제목 + 행 목록.
struct StatDetailCard<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let content: Content

    init(icon: String, tint: Color, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.content = content()
    }

    var body: some View {
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

            VStack(spacing: 14) { content }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// 값 하나(레이블 + 우측 숫자)만 있는 일반 행.
struct StatDetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
    }
}

/// 0~100% 비율 행 — 숫자만으로는 비교가 어려워서 막대를 같이 그린다.
struct StatRateRow: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(pct)
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

    private var pct: String { "\(Int((value * 100).rounded()))%" }
}

/// 0을 기준으로 양수=파랑(우세)/음수=빨강(열세)로 색칠하는 공용 규칙.
func statRatingColor(_ value: Double) -> Color {
    value > 0 ? .blue : value < 0 ? .red : .secondary
}

/// 승률 도넛 링. 원형 트랙 위에 승률만큼 색을 채운다.
struct WinRateRing: View {
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
