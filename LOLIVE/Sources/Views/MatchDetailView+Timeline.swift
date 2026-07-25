//
//  MatchDetailView+Timeline.swift
//  LOLIVE
//
//  경기 상세 화면의 킬 타임라인 카드.
//

import SwiftUI

extension MatchDetailView {

    func killTimelineCard(window: GameWindow, kills: [KillEvent]) -> some View {
        let blueIds = Set(window.bluePlayers.map(\.participantId))
        let blueKills = kills.filter { isBlueKill($0, blueIds: blueIds, blueTeamId: window.blueTeamId) }
        let redKills  = kills.filter { !isBlueKill($0, blueIds: blueIds, blueTeamId: window.blueTeamId) }
        let blueTeam  = teamFor(windowTeamId: window.blueTeamId)
        let redTeam   = teamFor(windowTeamId: window.redTeamId)
        let maxMs     = max(kills.map(\.gameTimeMs).max() ?? 0, 20 * 60 * 1000)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("킬 타임라인")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 7, height: 7)
                    Text("\(blueTeam?.code ?? "Blue")  \(blueKills.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("\(redTeam?.code ?? "Red")  \(redKills.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            GeometryReader { geo in
                let w = geo.size.width - 32
                ZStack(alignment: .topLeading) {
                    // 중앙 축
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: w, height: 0.5)
                        .offset(x: 16, y: 34)

                    // Blue 킬 점
                    ForEach(Array(blueKills.enumerated()), id: \.offset) { _, kill in
                        Circle()
                            .fill(Color.blue.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .offset(x: 16 + killXPos(kill.gameTimeMs, maxMs: maxMs, width: w) - 4,
                                    y: 22)
                    }

                    // Red 킬 점
                    ForEach(Array(redKills.enumerated()), id: \.offset) { _, kill in
                        Circle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .offset(x: 16 + killXPos(kill.gameTimeMs, maxMs: maxMs, width: w) - 4,
                                    y: 44)
                    }

                    // 분 단위 레이블
                    ForEach(killTimeMarkers(maxMs: maxMs), id: \.self) { min in
                        Text(min == 0 ? "0" : "\(min)m")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .offset(x: 16 + killXPos(min * 60_000, maxMs: maxMs, width: w) - 6,
                                    y: 48)
                    }
                }
            }
            .frame(height: 72)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func isBlueKill(_ kill: KillEvent, blueIds: Set<Int>, blueTeamId: String) -> Bool {
        if !kill.killerTeamId.isEmpty { return kill.killerTeamId == blueTeamId }
        return blueIds.contains(kill.killerParticipantId)
    }

    private func killXPos(_ ms: Int, maxMs: Int, width: CGFloat) -> CGFloat {
        guard maxMs > 0 else { return 0 }
        return CGFloat(ms) / CGFloat(maxMs) * width
    }

    private func killTimeMarkers(maxMs: Int) -> [Int] {
        let maxMin = maxMs / 60_000
        let step = maxMin > 45 ? 15 : maxMin > 30 ? 10 : 5
        return Array(stride(from: 0, through: maxMin, by: step))
    }
}
