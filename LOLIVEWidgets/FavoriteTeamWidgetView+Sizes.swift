//
//  FavoriteTeamWidgetView+Sizes.swift
//  LOLIVEWidgets
//
//  Small / Medium / Large 크기별 위젯 뷰.
//

import SwiftUI

extension FavoriteTeamWidgetView {

    // MARK: - Small

    var smallView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                teamLogo(data: entry.teamImageData, size: 48)
                Text(entry.teamCode)
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                Text(entry.leagueName)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)

            if let match = entry.nextMatch {
                VStack(spacing: 5) {
                    if match.isLive {
                        liveBadge
                    } else {
                        Text("다음 경기").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        teamLogo(data: entry.opponentImageData, size: 18)
                        Text("vs \(match.opponentCode)")
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    matchTimeView(match: match, compact: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("예정된 경기 없음")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if entry.totalTeams > 1 {
                Spacer(minLength: 10)
                carouselDots
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium

    var mediumView: some View {
        VStack(spacing: 0) {
            if let match = entry.nextMatch {
                HStack(spacing: 0) {
                    VStack(spacing: 5) {
                        teamLogo(data: entry.teamImageData, size: 44)
                        Text(entry.teamCode)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        if match.isLive {
                            liveBadge
                            matchTimeView(match: match, compact: true)
                        } else {
                            matchTimeView(match: match, compact: false)
                        }
                        Text(entry.leagueName)
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .frame(width: 110)

                    VStack(spacing: 5) {
                        teamLogo(data: entry.opponentImageData, size: 44)
                        Text(match.opponentCode)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 14) {
                    teamLogo(data: entry.teamImageData, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.teamCode)
                            .font(.title3).fontWeight(.bold).foregroundStyle(.primary)
                        Text(entry.leagueName)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("예정된 경기 없음")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            if entry.totalTeams > 1 {
                Spacer(minLength: 12)
                carouselControls
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Large (모든 팀 목록)

    var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("즐겨찾기")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Text("즐겨찾기 팀")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)

            ForEach(Array(entry.allTeams.prefix(5).enumerated()), id: \.offset) { i, info in
                if i > 0 {
                    Divider().padding(.leading, 60)
                }
                largeTeamRow(info)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func largeTeamRow(_ info: TeamRowInfo) -> some View {
        HStack(spacing: 12) {
            teamLogo(data: info.teamImageData, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.teamCode)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.primary)
                Text(info.leagueName)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if let match = info.nextMatch {
                if match.isLive {
                    VStack(alignment: .trailing, spacing: 2) {
                        liveBadge
                        Text(scoreText(match) ?? "vs \(match.opponentCode)")
                            .font(.caption2).fontWeight(.medium).foregroundStyle(.primary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("vs \(match.opponentCode)")
                            .font(.caption2).fontWeight(.medium).foregroundStyle(.primary)
                        largeMatchTimeView(match: match)
                    }
                }
                teamLogo(data: info.opponentImageData, size: 28)
            } else {
                Text("경기 없음")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}
