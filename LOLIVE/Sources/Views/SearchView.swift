//
//  SearchView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct SearchView: View {
    let focusTrigger: Int

    @State private var viewModel = SearchViewModel()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Query private var favoriteTeams: [FavoriteTeam]
    @Query private var favoritePlayers: [FavoritePlayer]
    @Environment(\.modelContext) private var modelContext

    private var results: [SearchViewModel.SearchResult] {
        viewModel.results(for: searchText)
    }

    // FavoritesView와 동일한 이유로 NavigationStack을 두지 않는다 —
    // "더보기" 목록이 이미 UINavigationController를 제공하므로 여기서 또 씌우면 백버튼이 2개가 된다.
    var body: some View {
        VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("리그, 팀, 선수 검색", text: $searchText)
                        .font(.subheadline)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if viewModel.isLoading && searchText.isEmpty {
                        LoadingView()
                    } else if viewModel.loadFailed && searchText.isEmpty {
                        ErrorRetryView("검색 데이터를 불러올 수 없습니다") { Task { await viewModel.load() } }
                    } else if searchText.isEmpty {
                        emptyPrompt
                    } else if results.isEmpty {
                        noResults
                    } else {
                        resultList
                    }
                }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("검색")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .task(id: focusTrigger) {
            guard focusTrigger > 0 else { return }
            try? await Task.sleep(for: .milliseconds(150))
            isSearchFocused = true
        }
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
        let isFav = favoriteTeams.contains { $0.teamCode == team.code }
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
                PlayerAvatarView(imageURL: player.imageURL, size: 36)
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
            favoriteTeams.first { $0.teamCode == team.code }.map { modelContext.delete($0) }
        } else {
            guard !favoriteTeams.contains(where: { $0.teamCode == team.code }) else { return }
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
    SearchView(focusTrigger: 0)
        .preferredColorScheme(.dark)
}
