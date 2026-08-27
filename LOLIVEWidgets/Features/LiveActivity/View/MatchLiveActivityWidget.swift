//
//  MatchLiveActivityWidget.swift
//  LOLIVEWidgets
//

import ActivityKit
import WidgetKit
import SwiftUI
struct MatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            LockScreenLiveActivityView(
                attributes: context.attributes,
                state: context.state
            )
            // 시스템 라이트/다크 모드에 맞춰 자동으로 흰색/검정으로 전환되는 시맨틱 컬러 —
            // 예전엔 항상 검정 고정이라 라이트 모드에서도 어두운 카드로 떠 있었음.
            .activityBackgroundTint(Color(uiColor: .systemBackground))
            .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    expandedTeamView(
                        imageData: context.attributes.teamAImageData,
                        code: context.attributes.teamACode,
                        imageURL: context.attributes.teamAImageURL,
                        score: context.state.scoreA,
                        alignment: .leading
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTeamView(
                        imageData: context.attributes.teamBImageData,
                        code: context.attributes.teamBCode,
                        imageURL: context.attributes.teamBImageURL,
                        score: context.state.scoreB,
                        alignment: .trailing
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text("Game \(context.state.currentGame)")
                            .font(.caption2).fontWeight(.semibold)
                        Text(context.attributes.leagueName)
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // 위(.center)에 이미 "Game N"·리그명이 있어서 아래 줄은 상태만 —
                    // 예전엔 여기도 "LIVE · Game N · 리그명"을 그대로 반복해서 두 줄이 똑같아 보였음.
                    HStack(spacing: 4) {
                        if context.state.isFinished {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("경기종료")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else if context.state.isLive {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.caption2).fontWeight(.bold)
                                .foregroundStyle(.red)
                        } else {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("시작 중...")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(context.attributes.leagueName), " +
                        (context.state.isFinished ? "경기종료" : (context.state.isLive ? "라이브, \(context.state.currentGame)세트" : "시작 중"))
                    )
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    DynamicIslandTeamLogo(imageData: context.attributes.teamAImageData,
                                          teamCode: context.attributes.teamACode,
                                          imageURL: context.attributes.teamAImageURL,
                                          size: 14)
                    Text("\(context.state.scoreA)")
                        .font(.caption2).fontWeight(.bold)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(context.attributes.teamAName) \(context.state.scoreA)점")
            } compactTrailing: {
                HStack(spacing: 3) {
                    Text("\(context.state.scoreB)")
                        .font(.caption2).fontWeight(.bold)
                    DynamicIslandTeamLogo(imageData: context.attributes.teamBImageData,
                                          teamCode: context.attributes.teamBCode,
                                          imageURL: context.attributes.teamBImageURL,
                                          size: 14)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(context.attributes.teamBName) \(context.state.scoreB)점")
            } minimal: {
                Text("\(context.state.scoreA)-\(context.state.scoreB)")
                    .font(.system(size: 10)).fontWeight(.bold)
                    .accessibilityLabel(
                        "\(context.attributes.teamAName) \(context.state.scoreA) 대 \(context.attributes.teamBName) \(context.state.scoreB)"
                    )
            }
        }
    }

    // MARK: - Dynamic Island expanded helper

    private func expandedTeamView(imageData: Data?, code: String, imageURL: String?, score: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            DynamicIslandTeamLogo(imageData: imageData, teamCode: code, imageURL: imageURL, size: 24)
            Text(code)
                .font(.caption2).fontWeight(.bold)
                .lineLimit(1)
            Text("\(score)")
                .font(.subheadline).fontWeight(.bold)
                .foregroundStyle(score > 0 ? Color.orange : Color.secondary)
                .widgetAccentable()
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(code) \(score)점")
    }
}

// MARK: - Dynamic Island 로고 (widgetRenderingMode 대응 위해 별도 View로 분리)

/// Dynamic Island는 하드웨어 카메라 하우징 자리라 배경이 항상 검정으로 고정이지만, 저조도·집중모드
/// 등에서 vibrant(단색) 렌더링으로 전환될 수 있다 — 그럴 땐 색깔 로고 대신 팀 코드 텍스트로 대체.
private struct DynamicIslandTeamLogo: View {
    let imageData: Data?
    let teamCode: String
    let imageURL: String?
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode != .fullColor {
            fallback
        } else if let img = sharedHiResLogo(teamCode: teamCode) ?? imageData.flatMap({ UIImage(data: $0) }) {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
        } else if let urlStr = imageURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: fallback
                }
            }
            .frame(width: size, height: size)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Text(String(teamCode.prefix(1)))
            .font(.system(size: size * 0.7, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
    }
}


// MARK: - Previews

#Preview("잠금화면 Live Activity", as: .content, using: MatchActivityAttributes(
    matchId: "preview",
    teamAName: "T1", teamACode: "T1",
    teamAImageURL: nil, teamAImageData: nil,
    teamBName: "Gen.G", teamBCode: "GEN",
    teamBImageURL: nil, teamBImageData: nil,
    leagueName: "LCK", blockName: "5주 차"
)) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchActivityAttributes.ContentState(scoreA: 1, scoreB: 0, currentGame: 2, isLive: true)
    MatchActivityAttributes.ContentState(scoreA: 2, scoreB: 1, currentGame: 3, isLive: true)
    MatchActivityAttributes.ContentState(scoreA: 2, scoreB: 1, currentGame: 3, isLive: false, isFinished: true)
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: MatchActivityAttributes(
    matchId: "preview",
    teamAName: "T1", teamACode: "T1",
    teamAImageURL: nil, teamAImageData: nil,
    teamBName: "Gen.G", teamBCode: "GEN",
    teamBImageURL: nil, teamBImageData: nil,
    leagueName: "LCK", blockName: "5주 차"
)) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchActivityAttributes.ContentState(scoreA: 1, scoreB: 0, currentGame: 2, isLive: true)
}
