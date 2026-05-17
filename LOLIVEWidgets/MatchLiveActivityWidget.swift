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
            .activityBackgroundTint(Color.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandExpandedView(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                        Text("LIVE · Game \(context.state.currentGame)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                        Text(context.attributes.leagueName)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    teamLogoInline(teamCode: context.attributes.teamACode, size: 14)
                    Text("\(context.state.scoreA)")
                        .font(.caption2).fontWeight(.bold)
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Text("\(context.state.scoreB)")
                        .font(.caption2).fontWeight(.bold)
                    teamLogoInline(teamCode: context.attributes.teamBCode, size: 14)
                }
            } minimal: {
                Text("\(context.state.scoreA)-\(context.state.scoreB)")
                    .font(.system(size: 10)).fontWeight(.bold)
            }
        }
    }

    private func teamLogoInline(teamCode: String, size: CGFloat) -> some View {
        Group {
            if let data = SharedDataService.loadTeamImageData(teamCode: teamCode),
               let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Text(String(teamCode.prefix(1)))
                    .font(.system(size: size * 0.75, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Lock Screen (FotMob style)

struct LockScreenLiveActivityView: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    private var imgA: Data? { SharedDataService.loadTeamImageData(teamCode: attributes.teamACode) }
    private var imgB: Data? { SharedDataService.loadTeamImageData(teamCode: attributes.teamBCode) }

    var body: some View {
        HStack(spacing: 0) {
            // ── 팀 A ─────────────────────
            HStack(spacing: 8) {
                teamLogo(data: imgA, code: attributes.teamACode, size: 38)
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
                HStack(spacing: 3) {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                    Text("· G\(state.currentGame)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(attributes.leagueName)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .fixedSize()

            // ── 팀 B ─────────────────────
            HStack(spacing: 8) {
                Text(attributes.teamBCode)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                teamLogo(data: imgB, code: attributes.teamBCode, size: 38)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func teamLogo(data: Data?, code: String, size: CGFloat) -> some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                // 이미지 없을 때 팀 코드 뱃지로 대체
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Text(String(code.prefix(3)))
                            .font(.system(size: size * 0.28, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Dynamic Island Expanded

struct DynamicIslandExpandedView: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            teamChip(
                code: attributes.teamACode,
                imageData: SharedDataService.loadTeamImageData(teamCode: attributes.teamACode),
                score: state.scoreA,
                isLeading: true
            )

            Spacer()

            VStack(spacing: 1) {
                Text("Game \(state.currentGame)")
                    .font(.caption2).fontWeight(.semibold)
                Text(attributes.leagueName)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            teamChip(
                code: attributes.teamBCode,
                imageData: SharedDataService.loadTeamImageData(teamCode: attributes.teamBCode),
                score: state.scoreB,
                isLeading: false
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func teamChip(code: String, imageData: Data?, score: Int, isLeading: Bool) -> some View {
        HStack(spacing: 5) {
            if isLeading {
                teamLogo(data: imageData, code: code, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(code).font(.caption2).fontWeight(.bold)
                    Text("\(score)").font(.caption2).fontWeight(.semibold).foregroundStyle(.blue)
                }
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(code).font(.caption2).fontWeight(.bold)
                    Text("\(score)").font(.caption2).fontWeight(.semibold).foregroundStyle(.red)
                }
                teamLogo(data: imageData, code: code, size: 22)
            }
        }
    }

    private func teamLogo(data: Data?, code: String, size: CGFloat) -> some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Text(String(code.prefix(1)))
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
        }
        .frame(width: size, height: size)
    }
}
