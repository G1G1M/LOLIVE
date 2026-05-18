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
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                HStack(spacing: 0) {
                    teamView(team: match.teamA, alignment: .trailing)

                    centerView

                    teamView(team: match.teamB, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(height: 80)
    }

    // MARK: - Team

    private func teamView(team: Team, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: .center, spacing: 4) {
            CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                .frame(width: 36, height: 36)

            Text(team.code)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Center

    private var centerView: some View {
        VStack(spacing: 4) {
            if isLive {
                liveBadge
            } else {
                timeText
            }

            HStack(spacing: 8) {
                Text("\(match.scoreA)")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("-")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(match.scoreB)")
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
        .frame(width: 80)
    }

    // MARK: - LIVE Badge

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
            Text("LIVE")
                .font(.caption).fontWeight(.bold).foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.red.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Time

    private var timeText: some View {
        Group {
            if match.state == .completed {
                Text("종료")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let remaining = match.startTime.timeIntervalSince(context.date)
                    if remaining > 0 && remaining < 3600 {
                        Text("\(Int(remaining / 60))분 후")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(match.startTime, format: .dateTime.hour().minute()
                            .locale(Locale(identifier: "ko_KR")))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    let league = League(id: "1", slug: "lck", name: "LCK", region: "Korea", imageURL: nil)
    let t1 = Team(id: "t1", name: "T1", code: "T1", imageURL: nil)
    let gen = Team(id: "gen", name: "Gen.G", code: "GEN", imageURL: nil)
    let match = Match(id: "m1", league: league, teamA: t1, teamB: gen,
                      scoreA: 1, scoreB: 2, startTime: Date(), state: .inProgress)

    VStack(spacing: 12) {
        MatchCardView(match: match, isLive: true)
        MatchCardView(match: match, isLive: false)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
    .preferredColorScheme(.dark)
}
