//
//  LockScreenLiveActivityView.swift
//  LOLIVEWidgets
//
//  Live Activity의 잠금화면 배너. Dynamic Island 쪽 표현은 MatchLiveActivityWidget.swift에 있다.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LockScreenLiveActivityView: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var statusText: String {
        if state.isFinished { return "경기종료" }
        return state.isLive ? "LIVE · Game \(state.currentGame)" : "시작 중"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {

                // ── 팀 A (로고 위, 팀명 아래) ─────
                VStack(spacing: 6) {
                    teamLogo(imageData: attributes.teamAImageData,
                             teamCode: attributes.teamACode,
                             imageURL: attributes.teamAImageURL,
                             size: 38)
                    Text(attributes.teamACode)
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

                // ── 스코어 (중앙, 리그명이 스코어 위) ─────────────
                VStack(spacing: 8) {
                    Text(attributes.leagueName)
                        .font(.system(size: 10)).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                    if state.isFinished {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text("경기종료")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                    } else if state.isLive {
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
                }
                .padding(.horizontal, 16)

                // ── 팀 B (로고 위, 팀명 아래) ─────
                VStack(spacing: 6) {
                    teamLogo(imageData: attributes.teamBImageData,
                             teamCode: attributes.teamBCode,
                             imageURL: attributes.teamBImageURL,
                             size: 38)
                    Text(attributes.teamBCode)
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }

            // ── 맨 아래: 라운드/주차 정보 ─────────────
            if let blockName = attributes.blockName, !blockName.isEmpty {
                Text(blockName)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        // 컴포넌트 크기는 원래대로 두고, 세로 길이만 140pt로 고정 — 내용은 가운데 정렬돼
        // 남는 위아래 공간에 여백이 생긴다.
        .frame(height: 140)
        // 팀 로고·코드·스코어·상태가 VoiceOver로 따로따로 읽히던 걸 한 문장으로 통합
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(attributes.leagueName), \(attributes.teamAName) \(state.scoreA) 대 \(attributes.teamBName) \(state.scoreB), \(statusText)"
            + (attributes.blockName.map { ", \($0)" } ?? "")
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
