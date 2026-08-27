//
//  TeamDetailView+H2H.swift
//  LOLIVE
//
//  팀 상세 "상대 전적" 탭과, "최근경기" 탭에 넘길 항목 변환.
//

import SwiftUI

extension TeamDetailView {

    var h2hCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.h2hRecords) { record in
                HStack(spacing: 12) {
                    LogoBadgeView(imageURL: record.opponent.imageURL, size: 36)

                    Text(record.opponent.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Text("\(record.wins)승 \(record.losses)패")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(record.wins > record.losses ? .primary : .secondary)

                    Text(String(format: "%.0f%%", record.winRate * 100))
                        .font(.caption).fontWeight(.bold)
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(record.winRate >= 0.5 ? .blue : .red)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                if record.id != viewModel.h2hRecords.last?.id {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 최근경기 카드는 "내 팀 기준"으로 상대/스코어를 뒤집어 보여줘야 해서 여기서 변환한다.
    var recentMatchItems: [RecentMatchesCard.Item] {
        viewModel.recentMatches.map { match in
            let isTeamA  = match.teamA.id == team.id || match.teamA.code == team.code
            let myScore  = isTeamA ? match.scoreA : match.scoreB
            let oppScore = isTeamA ? match.scoreB : match.scoreA
            let opponent = isTeamA ? match.teamB : match.teamA
            return RecentMatchesCard.Item(id: match.id, match: match, opponent: opponent,
                                          myScore: myScore, oppScore: oppScore,
                                          won: myScore > oppScore, date: match.startTime)
        }
    }
}
