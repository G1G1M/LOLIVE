//
//  MatchLiveActivityWidget.swift
//  LOLIVEWidgets
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - App Group 고화질 로고 로더

/// 메인 앱(LiveActivityService)이 App Group에 저장해둔 고화질 로고(180×180 PNG)를 읽는다.
/// ActivityKit attributes는 4KB 제한 때문에 저화질 썸네일만 담을 수 있으므로
/// 파일이 있으면 이쪽을 우선 사용한다. 파일명 규칙은 메인 앱과 동일해야 한다.
func sharedHiResLogo(teamCode: String) -> UIImage? {
    guard let base = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SharedDataService.appGroupId) else { return nil }
    let safe = teamCode
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    let url = base.appendingPathComponent("LiveActivityLogos/\(safe).png")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
}

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
                    HStack(spacing: 4) {
                        if context.state.isLive {
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                            Text("LIVE · Game \(context.state.currentGame)")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("시작 중...")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("·").foregroundStyle(.secondary)
                        Text(context.attributes.leagueName)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(context.attributes.leagueName), " +
                        (context.state.isLive ? "라이브, \(context.state.currentGame)세트" : "시작 중")
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

// MARK: - Lock Screen (이전 디자인 복원)

struct LockScreenLiveActivityView: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var statusText: String {
        state.isLive ? "LIVE · Game \(state.currentGame)" : "시작 중"
    }

    var body: some View {
        HStack(spacing: 0) {

            // ── 팀 A ─────────────────────
            HStack(spacing: 12) {
                teamLogo(imageData: attributes.teamAImageData,
                         teamCode: attributes.teamACode,
                         imageURL: attributes.teamAImageURL,
                         size: 38)
                Text(attributes.teamACode)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)

            // ── 스코어 (중앙) ─────────────
            // 컴포넌트 크기는 그대로 두고, 요소 사이 간격만 넉넉하게 — 세로 길이를 140pt로
            // 고정한 뒤에도 안쪽 요소들끼리 다닥다닥 붙어 있어서 위아래에 빈 여백만 크게 남고
            // 정작 콘텐츠는 뭉쳐 보였다.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(state.scoreA)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("–")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("\(state.scoreB)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .widgetAccentable()
                .accessibilityHidden(true)
                if state.isLive {
                    HStack(spacing: 5) {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                        Text("· G\(state.currentGame)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text("시작 중...")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                }
                Text(attributes.leagueName)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)

            // ── 팀 B ─────────────────────
            HStack(spacing: 12) {
                Text(attributes.teamBCode)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                teamLogo(imageData: attributes.teamBImageData,
                         teamCode: attributes.teamBCode,
                         imageURL: attributes.teamBImageURL,
                         size: 38)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        // 컴포넌트 크기는 원래대로 두고, 세로 길이만 140pt로 고정 — 내용은 가운데 정렬돼
        // 남는 위아래 공간에 여백이 생긴다.
        .frame(height: 140)
        // 팀 로고·코드·스코어·상태가 VoiceOver로 따로따로 읽히던 걸 한 문장으로 통합
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(attributes.leagueName), \(attributes.teamAName) \(state.scoreA) 대 \(attributes.teamBName) \(state.scoreB), \(statusText)"
        )
    }

    @ViewBuilder
    private func teamLogo(imageData: Data?, teamCode: String, imageURL: String?, size: CGFloat) -> some View {
        // 잠금화면이 모노크롬/vibrant 모드로 렌더링될 땐(접근성 설정, 저조도 등) 색깔 있는 로고
        // 이미지가 뭉개져 잘 안 보일 수 있어서, 그럴 땐 로고 대신 팀 코드 텍스트로 대체한다.
        if renderingMode != .fullColor {
            logoPlaceholder(code: teamCode, size: size)
                .frame(width: size, height: size)
        } else if let img = sharedHiResLogo(teamCode: teamCode)
            ?? imageData.flatMap({ UIImage(data: $0) }) {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
        } else if let urlStr = imageURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: logoPlaceholder(code: teamCode, size: size)
                }
            }
            .frame(width: size, height: size)
        } else {
            logoPlaceholder(code: teamCode, size: size)
                .frame(width: size, height: size)
        }
    }

    private func logoPlaceholder(code: String, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.primary.opacity(0.08))
            .overlay(
                Text(String(code.prefix(3)))
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Previews

#Preview("잠금화면 Live Activity", as: .content, using: MatchActivityAttributes(
    matchId: "preview",
    teamAName: "T1", teamACode: "T1",
    teamAImageURL: nil, teamAImageData: nil,
    teamBName: "Gen.G", teamBCode: "GEN",
    teamBImageURL: nil, teamBImageData: nil,
    leagueName: "LCK"
)) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchActivityAttributes.ContentState(scoreA: 1, scoreB: 0, currentGame: 2, isLive: true)
    MatchActivityAttributes.ContentState(scoreA: 2, scoreB: 1, currentGame: 3, isLive: true)
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: MatchActivityAttributes(
    matchId: "preview",
    teamAName: "T1", teamACode: "T1",
    teamAImageURL: nil, teamAImageData: nil,
    teamBName: "Gen.G", teamBCode: "GEN",
    teamBImageURL: nil, teamBImageData: nil,
    leagueName: "LCK"
)) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchActivityAttributes.ContentState(scoreA: 1, scoreB: 0, currentGame: 2, isLive: true)
}
