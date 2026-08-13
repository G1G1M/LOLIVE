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
                    .lineLimit(1)
                Text(entry.leagueName)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.teamName), \(entry.leagueName)")

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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nextMatchAccessibilityLabel(match))
            } else {
                Text("예정된 경기 없음")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if entry.totalTeams > 1 {
                Spacer(minLength: 10)
                carouselDots
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium

    var mediumView: some View {
        GeometryReader { geo in
            // 중앙 패널(시간/스코어) 너비를 고정값 대신 위젯 실제 캔버스 폭의 비율로 계산 —
            // 기기별로(SE~Pro Max) Medium 위젯의 실제 폭이 조금씩 달라서, 고정 110pt로는
            // 작은 기기에서 양옆 팀 패널이 좁아지고 큰 기기에서는 가운데만 휑하게 남을 수 있음.
            let midWidth = max(90, min(130, geo.size.width * 0.32))

            VStack(spacing: 0) {
                if let match = entry.nextMatch {
                    HStack(spacing: 0) {
                        VStack(spacing: 5) {
                            teamLogo(data: entry.teamImageData, size: 44)
                            Text(entry.teamCode)
                                .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                                .lineLimit(1)
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
                                .lineLimit(1)
                                .padding(.top, 2)
                        }
                        .frame(width: midWidth)

                        VStack(spacing: 5) {
                            teamLogo(data: entry.opponentImageData, size: 44)
                            Text(match.opponentCode)
                                .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(nextMatchAccessibilityLabel(match, myTeam: entry.teamName))
                } else {
                    HStack(spacing: 14) {
                        teamLogo(data: entry.teamImageData, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.teamCode)
                                .font(.title3).fontWeight(.bold).foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(entry.leagueName)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("예정된 경기 없음")
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.teamName), \(entry.leagueName), 예정된 경기 없음")
                }

                if entry.totalTeams > 1 {
                    Spacer(minLength: 12)
                    carouselControls
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    /// Small/Medium의 "다음 경기" 블록을 VoiceOver 한 문장으로 합칠 때 쓰는 문구.
    private func nextMatchAccessibilityLabel(
        _ match: WidgetNetworkService.NextMatchInfo, myTeam: String? = nil
    ) -> String {
        let team = myTeam ?? entry.teamName
        if match.isLive {
            let score = scoreText(match) ?? "라이브"
            return "\(team) vs \(match.opponentName), \(score)"
        }
        return "\(team) 다음 경기, vs \(match.opponentName)"
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
                    .lineLimit(1)
                Text(info.leagueName)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let match = info.nextMatch {
                if match.isLive {
                    VStack(alignment: .trailing, spacing: 2) {
                        liveBadge
                        Text(scoreText(match) ?? "vs \(match.opponentCode)")
                            .font(.caption2).fontWeight(.medium).foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("vs \(match.opponentCode)")
                            .font(.caption2).fontWeight(.medium).foregroundStyle(.primary)
                            .lineLimit(1)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(largeRowAccessibilityLabel(info))
    }

    private func largeRowAccessibilityLabel(_ info: TeamRowInfo) -> String {
        guard let match = info.nextMatch else {
            return "\(info.teamName), \(info.leagueName), 경기 없음"
        }
        if match.isLive {
            return "\(info.teamName), \(scoreText(match) ?? "vs \(match.opponentName), 라이브")"
        }
        return "\(info.teamName), 다음 경기 vs \(match.opponentName)"
    }
}
