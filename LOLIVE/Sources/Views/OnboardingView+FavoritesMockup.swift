//
//  OnboardingView+FavoritesMockup.swift
//  LOLIVE
//
//  온보딩 "즐겨찾기" 페이지 목업.
//

import SwiftUI

extension OnboardingView {

    var favoritesMockup: some View {
        let teamA   = loader.match?.teamA
        let teamB   = loader.match?.teamB
        let players = [loader.gameWindow?.bluePlayers.first,
                       loader.gameWindow?.redPlayers.first].compactMap { $0 }

        return VStack(spacing: 0) {
            // 팀 즐겨찾기
            HStack {
                Text("팀").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            VStack(spacing: 1) {
                favTeamRow(team: teamA, fallbackCode: "T1",  fallbackName: "티원",  fallbackColor: .blue)
                favTeamRow(team: teamB, fallbackCode: "GEN", fallbackName: "젠지",  fallbackColor: .purple)
            }

            // 선수 즐겨찾기
            HStack {
                Text("선수").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            VStack(spacing: 1) {
                if players.isEmpty {
                    // 로딩 전 플레이스홀더
                    favPlayerRowStatic(color: .blue,  role: "MID", name: "Faker",  team: "T1")
                    favPlayerRowStatic(color: .green, role: "JGL", name: "Canyon", team: "GEN")
                } else {
                    ForEach(players, id: \.id) { player in
                        favPlayerRowLive(player: player)
                    }
                }
            }

            Spacer().frame(height: 14)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.orange.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Sub-components

    private func favTeamRow(team: Team?, fallbackCode: String, fallbackName: String, fallbackColor: Color) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: team?.imageURL ?? ""))
                .frame(width: 36, height: 36)
                .background(team == nil ? fallbackColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(team?.name ?? fallbackName)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.primary)
                    .lineLimit(1)
                Text(team?.code ?? fallbackCode)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.subheadline).foregroundStyle(.yellow)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
    }

    private func favPlayerRowLive(player: PlayerStats) -> some View {
        HStack(spacing: 12) {
            Group {
                if let url = loader.playerImageURLs[player.summonerName] {
                    CachedAsyncImage(url: url)
                        .frame(width: 36, height: 36)
                } else {
                    ZStack {
                        Circle().fill(Color.secondary.opacity(0.2))
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: 36)
                    .task {
                        let name = player.summonerName
                        guard loader.playerImageURLs[name] == nil else { return }
                        AppDiskCache.clear(.oracleElixirPlayerImage(summonerName: name))
                        if let url = await OracleElixirService.shared.fetchPlayerImageURL(summonerName: name) {
                            loader.playerImageURLs[name] = url
                        }
                    }
                }
            }
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(player.summonerName)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.primary)
                Text(roleLabel(player.role))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.subheadline).foregroundStyle(.yellow)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
    }

    private func favPlayerRowStatic(color: Color, role: String, name: String, team: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption).fontWeight(.semibold).foregroundStyle(.primary)
                Text("\(team) · \(role)").font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.subheadline).foregroundStyle(.yellow)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
    }
}
