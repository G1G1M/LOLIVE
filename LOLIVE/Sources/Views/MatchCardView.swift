//
//  MatchCardView.swift
//  LOLIVE
//

import SwiftUI

struct MatchCardView: View {
    let match: Match
    var isLive: Bool = false

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 0) {
            teamSide(team: match.teamA, score: match.scoreA, opponentScore: match.scoreB, trailing: true)
            centerBlock
            teamSide(team: match.teamB, score: match.scoreB, opponentScore: match.scoreA, trailing: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Team Side

    private func teamSide(team: Team, score: Int, opponentScore: Int, trailing: Bool) -> some View {
        let dimmed = match.state == .completed && score < opponentScore
        return HStack(spacing: 12) {
            if trailing {
                Spacer()
                teamInfo(team: team, dimmed: dimmed, trailing: true)
                CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                    .frame(width: 38, height: 38)
                    .opacity(dimmed ? 0.5 : 1)
            } else {
                CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                    .frame(width: 38, height: 38)
                    .opacity(dimmed ? 0.5 : 1)
                teamInfo(team: team, dimmed: dimmed, trailing: false)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func teamInfo(team: Team, dimmed: Bool, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(team.code)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(dimmed ? Color.secondary : Color(.label))
        }
    }

    // MARK: - Center

    private var centerBlock: some View {
        VStack(spacing: 8) {
            statusBadge
            scoreOrVS
        }
        .frame(width: 88)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isLive {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
                Text("LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
        } else if match.state == .completed {
            Text("종료")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                let remaining = match.startTime.timeIntervalSince(ctx.date)
                if remaining > 0 && remaining < 3600 {
                    Text("\(Int(remaining / 60))분 후")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text(match.startTime, format: .dateTime.hour().minute()
                        .locale(Locale(identifier: "ko_KR")))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var scoreOrVS: some View {
        if match.state == .unstarted {
            Text("vs")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.quaternary)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(match.scoreA)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(scoreColor(mine: match.scoreA, opp: match.scoreB))
                Text(":")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.quaternary)
                Text("\(match.scoreB)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(scoreColor(mine: match.scoreB, opp: match.scoreA))
            }
        }
    }

    private func scoreColor(mine: Int, opp: Int) -> Color {
        guard match.state == .completed else { return Color(.label) }
        return mine > opp ? Color(.label) : Color.secondary
    }
}

#Preview {
    let league = League(id: "1", slug: "lck", name: "LCK", region: "Korea", imageURL: nil)
    let t1  = Team(id: "t1",  name: "T1",    code: "T1",  imageURL: nil)
    let gen = Team(id: "gen", name: "Gen.G", code: "GEN", imageURL: nil)

    VStack(spacing: 10) {
        MatchCardView(
            match: Match(id: "1", league: league, teamA: t1, teamB: gen,
                         scoreA: 0, scoreB: 0, startTime: Date().addingTimeInterval(3600),
                         state: .unstarted),
            isLive: false
        )
        MatchCardView(
            match: Match(id: "2", league: league, teamA: t1, teamB: gen,
                         scoreA: 1, scoreB: 0, startTime: Date(),
                         state: .inProgress),
            isLive: true
        )
        MatchCardView(
            match: Match(id: "3", league: league, teamA: t1, teamB: gen,
                         scoreA: 2, scoreB: 1, startTime: Date().addingTimeInterval(-7200),
                         state: .completed),
            isLive: false
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
