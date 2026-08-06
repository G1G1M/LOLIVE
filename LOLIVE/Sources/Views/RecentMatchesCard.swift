//
//  RecentMatchesCard.swift
//  LOLIVE
//
//  "최근 경기" 카드 — TeamDetailView와 LeaguePlayerDetailView에 각각 따로
//  구현되어 있던 동일한 UI(승/패 배지 + 상대 로고 + 이름/날짜 + 스코어 + 탭 시 경기 상세 이동)를 통일했다.
//

import SwiftUI

struct RecentMatchesCard: View {
    struct Item: Identifiable {
        let id: String
        let match: Match
        let opponent: Team
        let myScore: Int
        let oppScore: Int
        let won: Bool
        let date: Date
    }

    let items: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                NavigationLink(destination: MatchDetailView(match: item.match)) {
                    RecentMatchRow(opponent: item.opponent, myScore: item.myScore,
                                   oppScore: item.oppScore, won: item.won, date: item.date)
                }
                .buttonStyle(.plain)

                if item.id != items.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RecentMatchRow: View {
    let opponent: Team
    let myScore: Int
    let oppScore: Int
    let won: Bool
    let date: Date

    var body: some View {
        HStack(spacing: 12) {
            Text(won ? "W" : "L")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(won ? Color.blue : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            CachedAsyncImage(url: URL(string: opponent.imageURL ?? ""))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(opponent.name)")
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
                Text(date.formatted(.dateTime
                    .month(.abbreviated).day()
                    .locale(Locale(identifier: "ko_KR"))))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(myScore)-\(oppScore)")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(won ? .primary : .secondary)

            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
