//
//  OnboardingView+StatsMockup.swift
//  LOLIVE
//
//  온보딩 "경기 상세 통계" 페이지 목업.
//

import SwiftUI

extension OnboardingView {

    var statsMockup: some View {
        let teamA    = loader.match?.teamA
        let teamB    = loader.match?.teamB
        let blue     = loader.gameWindow?.bluePlayers.prefix(2) ?? []
        let red      = loader.gameWindow?.redPlayers.prefix(2) ?? []
        let bStats   = loader.gameWindow?.blueTeamStats
        let rStats   = loader.gameWindow?.redTeamStats
        let hasData  = loader.gameWindow != nil

        return VStack(spacing: 0) {
            // 팀 헤더
            HStack {
                HStack(spacing: 6) {
                    CachedAsyncImage(url: URL(string: teamA?.imageURL ?? ""))
                        .frame(width: 20, height: 20)
                        .background(hasData ? Color.clear : Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(teamA?.code ?? "Blue")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.blue)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(teamB?.code ?? "Red")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.red)
                    CachedAsyncImage(url: URL(string: teamB?.imageURL ?? ""))
                        .frame(width: 20, height: 20)
                        .background(hasData ? Color.clear : Color.red.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.white.opacity(0.07))

            // 팀 스탯
            VStack(spacing: 0) {
                statsRow("킬",   l: "\(bStats?.totalKills ?? 0)",        r: "\(rStats?.totalKills ?? 0)")
                Divider().background(.white.opacity(0.07))
                statsRow("골드", l: goldStr(bStats?.totalGold ?? 0),     r: goldStr(rStats?.totalGold ?? 0))
                Divider().background(.white.opacity(0.07))
                statsRow("타워", l: "\(bStats?.towers ?? 0)",            r: "\(rStats?.towers ?? 0)")
            }

            Divider().background(.white.opacity(0.12))

            // 블루팀 선수
            if !blue.isEmpty {
                sideLabel("Blue", color: .blue)
                ForEach(Array(blue.enumerated()), id: \.element.id) { i, p in
                    playerRow(p, sideColor: .blue)
                    if i < blue.count - 1 { Divider().background(.white.opacity(0.06)).padding(.leading, 44) }
                }
            }

            // 레드팀 선수
            if !red.isEmpty {
                Divider().background(.white.opacity(0.12))
                sideLabel("Red", color: .red)
                ForEach(Array(red.enumerated()), id: \.element.id) { i, p in
                    playerRow(p, sideColor: .red)
                    if i < red.count - 1 { Divider().background(.white.opacity(0.06)).padding(.leading, 44) }
                }
            }

            // 로딩 중 플레이스홀더
            if !hasData {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("선수 데이터 불러오는 중...")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.green.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Sub-components

    private func sideLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(color.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(color.opacity(0.07))
    }

    private func statsRow(_ label: String, l: String, r: String) -> some View {
        HStack {
            Text(l)
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .center)
            Text(r)
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 8)
    }

    private func playerRow(_ player: PlayerStats, sideColor: Color) -> some View {
        HStack(spacing: 8) {
            Text(roleLabel(player.role))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(sideColor.opacity(0.7))
                .frame(width: 24, alignment: .center)
            ChampionImageView(championId: player.championId, size: 24)
            Text(player.summonerName)
                .font(.caption).fontWeight(.medium).foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if player.hasStats {
                Text("\(player.kills)/\(player.deaths)/\(player.assists)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func goldStr(_ gold: Int) -> String {
        gold >= 1000 ? String(format: "%.1fk", Double(gold) / 1000) : "\(gold)"
    }
}
