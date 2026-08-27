//
//  OnboardingView+TodayMockup.swift
//  LOLIVE
//
//  온보딩 "오늘의 경기" 페이지 목업.
//

import SwiftUI

extension OnboardingView {

    var todayMockup: some View {
        let teamA   = loader.match?.teamA
        let teamB   = loader.match?.teamB
        let scoreA  = loader.match?.scoreA ?? 0
        let scoreB  = loader.match?.scoreB ?? 0
        let wonA    = scoreA > scoreB
        let loaded  = loader.match != nil

        return VStack(spacing: 0) {
            // 헤더
            HStack {
                statusPill(text: "완료", color: .secondary)
                Spacer()
                Text(loader.match?.league.name ?? "LCK")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider().background(Color(.separator))

            // 팀 스코어
            HStack(alignment: .center, spacing: 0) {
                // 팀 A
                VStack(spacing: 8) {
                    CachedAsyncImage(url: URL(string: teamA?.imageURL ?? ""))
                        .frame(width: 52, height: 52)
                        .background(loaded ? Color.clear : Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(teamA?.code ?? "—")
                        .font(.subheadline)
                        .fontWeight(wonA ? .bold : .regular)
                        .foregroundStyle(wonA ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)

                // 스코어
                HStack(spacing: 12) {
                    Text("\(scoreA)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(wonA ? .primary : .secondary)
                    Text(":")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("\(scoreB)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(!wonA ? .primary : .secondary)
                }
                .frame(width: 120)

                // 팀 B
                VStack(spacing: 8) {
                    CachedAsyncImage(url: URL(string: teamB?.imageURL ?? ""))
                        .frame(width: 52, height: 52)
                        .background(loaded ? Color.clear : Color.purple.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(teamB?.code ?? "—")
                        .font(.subheadline)
                        .fontWeight(!wonA ? .bold : .regular)
                        .foregroundStyle(!wonA ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)

            Divider().background(Color(.separator))

            // 하단 안내
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("경기 일정 및 결과를 한눈에")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.blue.opacity(0.18), lineWidth: 1))
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }
}
