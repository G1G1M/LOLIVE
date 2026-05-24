//
//  SearchView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var searchText = ""
    @Query private var favoriteTeams: [FavoriteTeam]
    @Query private var favoritePlayers: [FavoritePlayer]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var results: [SearchViewModel.SearchResult] {
        viewModel.results(for: searchText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if viewModel.isLoading && searchText.isEmpty {
                    ProgressView("불러오는 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchText.isEmpty {
                    emptyPrompt
                } else if results.isEmpty {
                    noResults
                } else {
                    resultList
                }
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "리그, 팀, 선수 검색")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - States

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("리그, 팀, 선수를 검색하세요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("'\(searchText)'에 대한 결과 없음")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result List

    private var resultList: some View {
        List(results) { result in
            resultRow(result)
                .listRowBackground(Color(.secondarySystemGroupedBackground))
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func resultRow(_ result: SearchViewModel.SearchResult) -> some View {
        switch result {
        case .league(let league):
            leagueRow(league)
        case .team(let team, let league):
            teamRow(team, league: league)
        case .player(let player, let league):
            playerRow(player, league: league)
        }
    }

    // MARK: - League Row

    private func leagueRow(_ league: League) -> some View {
        NavigationLink(destination: LeagueDetailView(league: league)) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: URL(string: league.imageURL ?? ""))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(league.name)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(league.region)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("리그")
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Team Row

    private func teamRow(_ team: Team, league: League) -> some View {
        let isFav = favoriteTeams.contains { $0.teamId == team.id }
        return NavigationLink(destination: TeamDetailView(team: team, league: league)) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(team.name)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(league.name)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("팀")
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                Button {
                    toggleFavoriteTeam(team, league: league, isFav: isFav)
                } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundStyle(isFav ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Player Row

    private func playerRow(_ player: Player, league: League) -> some View {
        let isFav = favoritePlayers.contains { $0.playerId == player.id }
        return NavigationLink(destination: LeaguePlayerDetailView(player: player, league: league)) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: URL(string: player.imageURL ?? ""))
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.summonerName)
                        .font(.subheadline).fontWeight(.semibold)
                    HStack(spacing: 4) {
                        Text(player.teamCode)
                        Text("·")
                        Text(league.name)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                roleTag(player.role)
                Button {
                    toggleFavoritePlayer(player, league: league, isFav: isFav)
                } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundStyle(isFav ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Helpers

    private func roleTag(_ role: String) -> some View {
        let label: String
        let color: Color
        switch role.lowercased() {
        case "top":             label = "TOP"; color = .orange
        case "jungle":          label = "JGL"; color = .green
        case "mid":             label = "MID"; color = .blue
        case "bottom", "bot":   label = "BOT"; color = .red
        case "support":         label = "SUP"; color = .purple
        default:                label = role.uppercased(); color = .secondary
        }
        return Text(label)
            .font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func toggleFavoriteTeam(_ team: Team, league: League, isFav: Bool) {
        if isFav {
            favoriteTeams.first { $0.teamId == team.id }.map { modelContext.delete($0) }
        } else {
            modelContext.insert(FavoriteTeam(team: team, league: league))
        }
    }

    private func toggleFavoritePlayer(_ player: Player, league: League, isFav: Bool) {
        if isFav {
            favoritePlayers.first { $0.playerId == player.id }.map { modelContext.delete($0) }
        } else {
            modelContext.insert(FavoritePlayer(player: player, league: league))
        }
    }
}

#Preview {
    SearchView()
        .preferredColorScheme(.dark)
}
