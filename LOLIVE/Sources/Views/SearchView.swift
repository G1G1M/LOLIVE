//
//  SearchView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @Query private var favoriteTeams: [FavoriteTeam]
    @Query private var favoritePlayers: [FavoritePlayer]
    @Environment(\.modelContext) private var modelContext

    private var results: [SearchViewModel.SearchResult] {
        viewModel.results(for: searchText)
    }

    // role: .search 탭이 .searchable을 인식하려면 이 탭의 콘텐츠가 자체 NavigationStack을
    // 가져야 한다 (ContentView의 TabView를 또 NavigationStack으로 감싸면 안 됨).
    // .searchable 자체는 탭을 누르면 검색창을 펼쳐주기만 할 뿐 키보드까지 자동으로 띄워주진
    // 않아서, isPresented가 true로 바뀌는 시점(탭 선택)에 .searchFocused로 직접 포커스를 준다.
    // .searchFocused는 iOS 18+ 전용이라 iOS 17 폴백 탭바에선 자동 포커스 없이 기존처럼 동작한다.
    var body: some View {
        if #available(iOS 18.0, *) {
            searchableContent
                .searchFocused($isSearchFocused)
                .onChange(of: isSearchPresented) { _, presented in
                    if presented { isSearchFocused = true }
                }
        } else {
            searchableContent
        }
    }

    private var searchableContent: some View {
        NavigationStack {
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
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "리그, 팀, 선수 검색")
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
        let color = RoleStyle.color(role)
        return Text(RoleStyle.label(role))
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
    SearchView()
        .preferredColorScheme(.dark)
}
