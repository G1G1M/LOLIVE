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
        // systemSmall 실제 캔버스는 기기마다 대략 150~170pt — 기존엔 로고 48pt + 여백들을
        // 합치면 최소 185pt가 필요해서 항상 넘쳤고, 아래쪽 콘텐츠가 잘리거나 겹쳐 보였다.
        // 로고를 줄이고 여백을 최소 여백(minLength) 위주로 다시 짜서 맞췄다.
        //
        // Medium과 달리 캐러셀에 참여하지 않는다 — 항상 대표 팀 하나만 고정으로 보여주므로
        // 점(dots)/버튼도 없다(대표 팀 개념은 representativeTeam 참고).
        Group {
            if let team = representativeTeam {
                VStack(spacing: 0) {
                    VStack(spacing: 3) {
                        teamLogo(data: team.teamImageData, size: 38)
                        Text(team.teamCode)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(team.leagueName)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(team.teamName), \(team.leagueName)")

                    Spacer(minLength: 8)

                    if let match = team.nextMatch {
                        VStack(spacing: 3) {
                            if match.isLive {
                                liveBadge
                            } else {
                                Text("다음 경기").font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                teamLogo(data: team.opponentImageData, size: 16)
                                Text("vs \(match.opponentCode)")
                                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            matchTimeView(match: match, compact: true)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(nextMatchAccessibilityLabel(match, myTeam: team.teamName))
                    } else {
                        Text("예정된 경기 없음")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                unconfiguredView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium

    var mediumView: some View {
        GeometryReader { geo in
            // 중앙 패널(시간/스코어) 너비를 고정값 대신 위젯 실제 캔버스 폭의 비율로 계산 —
            // 기기별로(SE~Pro Max) Medium 위젯의 실제 폭이 조금씩 달라서, 고정 110pt로는
            // 작은 기기에서 양옆 팀 패널이 좁아지고 큰 기기에서는 가운데만 휑하게 남을 수 있음.
            let midWidth = max(90, min(130, geo.size.width * 0.32))

            // 컴포넌트 크기(로고/폰트/캐러셀 버튼)는 그대로 두고, 요소 사이 간격을 한 번 더 벌림 —
            // 패딩 20으로 바꾼 뒤에도 요소들끼리 다닥다닥 붙어 보인다는 피드백 반영.
            VStack(spacing: 0) {
                if let match = entry.nextMatch {
                    HStack(spacing: 0) {
                        VStack(spacing: 8) {
                            teamLogo(data: entry.teamImageData, size: 44)
                            Text(entry.teamCode)
                                .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 8) {
                            if match.isLive {
                                liveBadge
                                matchTimeView(match: match, compact: true)
                            } else {
                                matchTimeView(match: match, compact: false)
                            }
                            Text(entry.leagueName)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.top, 3)
                        }
                        .frame(width: midWidth)

                        VStack(spacing: 8) {
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
                    HStack(spacing: 16) {
                        teamLogo(data: entry.teamImageData, size: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.teamCode)
                                .font(.title3).fontWeight(.bold).foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(entry.leagueName)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("예정된 경기 없음")
                                .font(.caption2).foregroundStyle(.secondary)
                                .padding(.top, 3)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.teamName), \(entry.leagueName), 예정된 경기 없음")
                }

                if entry.totalTeams > 1 {
                    Spacer(minLength: 10)
                    carouselControls
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
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
