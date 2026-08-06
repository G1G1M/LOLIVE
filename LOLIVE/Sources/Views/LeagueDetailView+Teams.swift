//
//  LeagueDetailView+Teams.swift
//  LOLIVE
//
//  리그 상세 화면의 팀 탭과 선수 탭.
//  - 팀 탭: 순위 카드 + 로스터(소속 선수 칩 그리드)
//  - 선수 탭: 리그 전체 선수 목록 (팀 로고 + 포지션 뱃지)
//

import SwiftUI

extension LeagueDetailView {

    // MARK: - 팀 탭

    var teamsContent: some View {
        let groups = viewModel.standingGroups
        return ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.standings.isEmpty {
                    EmptyStateView("팀 데이터가 없습니다").padding(.top, 60)
                } else if groups.isEmpty {
                    ForEach(viewModel.standings) { standing in
                        teamCard(standing: standing)
                    }
                } else {
                    // 그룹(Baron/Elder 등)이 있는 리그는 그룹명 헤더와 함께 표시
                    ForEach(groups, id: \.name) { group in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: 3, height: 14)
                            Text(group.name)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 4)

                        ForEach(group.standings) { standing in
                            teamCard(standing: standing)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func teamCard(standing: Standing) -> some View {
        let roster = viewModel.players.filter { $0.teamId == standing.team.id }
        return VStack(spacing: 0) {
            NavigationLink(value: standing.team) {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: URL(string: standing.team.imageURL ?? ""))
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(standing.team.name)
                            .font(.subheadline).fontWeight(.semibold)
                        Text("\(standing.wins)승 \(standing.losses)패")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("#\(standing.rank)")
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(standing.rank <= 3 ? .primary : .secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // 로스터가 있으면 카드 하단에 선수 칩 2열 그리드
            if !roster.isEmpty {
                Divider().padding(.horizontal, 16)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(roster) { player in
                        playerChip(player)
                    }
                }
                .padding(12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerChip(_ player: Player) -> some View {
        NavigationLink(value: player) {
            HStack(spacing: 8) {
                PlayerAvatarView(imageURL: player.imageURL, size: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(player.summonerName)
                        .font(.caption).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(roleLabel(player.role))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 선수 탭

    var playersContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.players.isEmpty {
                    EmptyStateView("선수 데이터가 없습니다").padding(.top, 60)
                } else {
                    ForEach(viewModel.players) { player in
                        playerRow(player)
                        if player.id != viewModel.players.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(16)
        }
    }

    private func playerRow(_ player: Player) -> some View {
        NavigationLink(value: player) {
            HStack(spacing: 12) {
                PlayerAvatarView(imageURL: player.imageURL, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.summonerName)
                        .font(.subheadline).fontWeight(.semibold)
                    if let first = player.firstName, let last = player.lastName,
                       !first.isEmpty || !last.isEmpty {
                        Text("\(first) \(last)".trimmingCharacters(in: .whitespaces))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    // 순위 데이터에서 팀 로고 URL 역참조
                    let teamImageURL = viewModel.standings
                        .first { $0.team.id == player.teamId }?.team.imageURL
                    CachedAsyncImage(url: URL(string: teamImageURL ?? ""))
                        .frame(width: 20, height: 20)

                    Text(player.teamCode)
                        .font(.caption).foregroundStyle(.secondary)

                    RoleBadge(role: player.role)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 포지션 헬퍼

    private func roleLabel(_ role: String) -> String { RoleStyle.label(role) }
}
