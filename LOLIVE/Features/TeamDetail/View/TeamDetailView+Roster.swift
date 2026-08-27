//
//  TeamDetailView+Roster.swift
//  LOLIVE
//
//  팀 상세 "선수단" 탭.
//

import SwiftUI

extension TeamDetailView {

    /// Riot getTeams 응답엔 주전/후보 구분이 없어 포지션당 여러 명이 그대로 옴(예: T1 BOT 4명).
    /// viewModel.currentStarterNames(최근 경기 실제 출전 명단)로 구할 수 있으면 주전을 먼저,
    /// 나머지는 "기타 등록 선수"로 분리 표시. 못 구했으면(원정경기 없음/API 실패) 기존처럼 전체 나열.
    private func isCurrentStarter(_ player: Player) -> Bool {
        viewModel.currentStarterNames.contains(player.summonerName.trimmingCharacters(in: .whitespaces).lowercased())
    }

    var rosterCard: some View {
        let starters = viewModel.currentStarterNames.isEmpty
            ? viewModel.players
            : viewModel.players.filter(isCurrentStarter)
        let bench = viewModel.currentStarterNames.isEmpty
            ? []
            : viewModel.players.filter { !isCurrentStarter($0) }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(starters) { player in
                NavigationLink {
                    LeaguePlayerDetailView(player: player, league: league)
                } label: {
                    playerRow(player)
                }
                .buttonStyle(.plain)
                if player.id != starters.last?.id || !bench.isEmpty {
                    Divider().padding(.leading, 68)
                }
            }

            if !bench.isEmpty {
                Text("기타 등록 선수")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)

                ForEach(bench) { player in
                    NavigationLink {
                        LeaguePlayerDetailView(player: player, league: league)
                    } label: {
                        playerRow(player)
                    }
                    .buttonStyle(.plain)
                    if player.id != bench.last?.id {
                        Divider().padding(.leading, 68)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerRow(_ player: Player) -> some View {
        HStack(spacing: 12) {
            PlayerAvatarView(imageURL: player.imageURL, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.summonerName)
                    .font(.subheadline).fontWeight(.semibold)
                if let first = player.firstName, let last = player.lastName,
                   !first.isEmpty || !last.isEmpty {
                    Text("\(first) \(last)".trimmingCharacters(in: .whitespaces))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            RoleBadge(role: player.role)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
