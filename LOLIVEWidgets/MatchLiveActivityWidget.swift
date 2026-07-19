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
            .activityBackgroundTint(Color.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
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
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    teamLogoView(imageData: context.attributes.teamAImageData,
                                 teamCode: context.attributes.teamACode,
                                 imageURL: context.attributes.teamAImageURL,
                                 size: 14)
                    Text("\(context.state.scoreA)")
                        .font(.caption2).fontWeight(.bold)
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Text("\(context.state.scoreB)")
                        .font(.caption2).fontWeight(.bold)
                    teamLogoView(imageData: context.attributes.teamBImageData,
                                 teamCode: context.attributes.teamBCode,
                                 imageURL: context.attributes.teamBImageURL,
                                 size: 14)
                }
            } minimal: {
                Text("\(context.state.scoreA)-\(context.state.scoreB)")
                    .font(.system(size: 10)).fontWeight(.bold)
            }
        }
    }

    // MARK: - Logo helper

    @ViewBuilder
    func teamLogoView(imageData: Data?, teamCode: String, imageURL: String?, size: CGFloat) -> some View {
        // 1순위: App Group 고화질 파일 → 2순위: attributes 내장 썸네일 → 3순위: URL/텍스트 폴백
        if let img = sharedHiResLogo(teamCode: teamCode)
            ?? imageData.flatMap({ UIImage(data: $0) }) {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
        } else if let urlStr = imageURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: logoFallback(code: teamCode, size: size)
                }
            }
            .frame(width: size, height: size)
        } else {
            logoFallback(code: teamCode, size: size)
                .frame(width: size, height: size)
        }
    }

    private func logoFallback(code: String, size: CGFloat) -> some View {
        Text(String(code.prefix(1)))
            .font(.system(size: size * 0.7, weight: .bold))
            .foregroundStyle(.white)
    }

    // MARK: - Dynamic Island expanded helper

    private func expandedTeamView(imageData: Data?, code: String, imageURL: String?, score: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            teamLogoView(imageData: imageData, teamCode: code, imageURL: imageURL, size: 24)
            Text(code)
                .font(.caption2).fontWeight(.bold)
                .lineLimit(1)
            Text("\(score)")
                .font(.subheadline).fontWeight(.bold)
                .foregroundStyle(score > 0 ? Color.orange : Color.secondary)
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
    }
}

// MARK: - Lock Screen (이전 디자인 복원)

struct LockScreenLiveActivityView: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {

            // ── 팀 A ─────────────────────
            HStack(spacing: 8) {
                teamLogo(imageData: attributes.teamAImageData,
                         teamCode: attributes.teamACode,
                         imageURL: attributes.teamAImageURL,
                         size: 38)
                Text(attributes.teamACode)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // ── 스코어 (중앙) ─────────────
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(state.scoreA)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("–")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(state.scoreB)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                if state.isLive {
                    HStack(spacing: 3) {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                        Text("· G\(state.currentGame)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("시작 중...")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Text(attributes.leagueName)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)

            // ── 팀 B ─────────────────────
            HStack(spacing: 8) {
                Text(attributes.teamBCode)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                teamLogo(imageData: attributes.teamBImageData,
                         teamCode: attributes.teamBCode,
                         imageURL: attributes.teamBImageURL,
                         size: 38)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func teamLogo(imageData: Data?, teamCode: String, imageURL: String?, size: CGFloat) -> some View {
        // 1순위: App Group 고화질 파일 → 2순위: attributes 내장 썸네일 → 3순위: URL/텍스트 폴백
        if let img = sharedHiResLogo(teamCode: teamCode)
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
            .fill(Color.white.opacity(0.1))
            .overlay(
                Text(String(code.prefix(3)))
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
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
