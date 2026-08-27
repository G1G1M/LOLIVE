//
//  SearchView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct SearchView: View {
    /// X(취소) 버튼을 눌러 검색을 닫을 때 호출 — ContentView가 Today 탭으로 전환하는 데 사용
    var onCancel: () -> Void = {}

    @State private var viewModel = SearchViewModel()
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var selectedCategory: SearchCategory? = nil
    @Query private var favoriteTeams: [FavoriteTeam]
    @Query private var favoritePlayers: [FavoritePlayer]
    @Environment(\.modelContext) private var modelContext

    private enum SearchCategory: String, CaseIterable {
        case league = "리그"
        case team   = "팀"
        case player = "선수"
    }

    private var results: [SearchViewModel.SearchResult] {
        let all = viewModel.results(for: searchText)
        guard let selectedCategory else { return all }
        return all.filter {
            switch ($0, selectedCategory) {
            case (.league, .league), (.team, .team), (.player, .player): return true
            default: return false
            }
        }
    }

    // role: .search 탭이 .searchable을 인식하려면 이 탭의 콘텐츠가 자체 NavigationStack을
    // 가져야 한다 (ContentView의 TabView를 또 NavigationStack으로 감싸면 안 됨).
    // 탭을 누르면 검색창이 펼쳐지기만 하고(iOS 표준 Search Role 동작), 키보드는 검색창을
    // 직접 탭해야 뜬다 — 예전엔 탭 선택 즉시 자동 포커스를 줬는데, 의도치 않게 키보드가
    // 바로 뜨는 게 불편하다는 피드백으로 되돌림.
    // X(취소) 버튼을 누르면 isPresented가 true→false로 바뀌는 걸 감지해 Today 탭으로 이동시킨다.
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSearchPresented {
                    categoryFilterBar
                }
                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if viewModel.isLoading {
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
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            // Match.self/League.self는 탭 루트에서 한 번씩만 등록(LeagueDetailView.swift 주석 참고).
            .navigationDestination(for: Match.self) { match in
                MatchDetailView(match: match)
            }
            .navigationDestination(for: League.self) { league in
                if league.isInternationalTournament {
                    TournamentDetailView(league: league)
                } else {
                    LeagueDetailView(league: league)
                }
            }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "리그, 팀, 선수 검색")
        .onChange(of: isSearchPresented) { wasPresented, presented in
            if wasPresented && !presented { onCancel(); selectedCategory = nil }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Category Filter (애플뮤직 스타일)

    private var categoryFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(SearchCategory.allCases, id: \.self) { category in
                SelectableChip(isSelected: selectedCategory == category) {
                    selectedCategory = selectedCategory == category ? nil : category
                } label: {
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(selectedCategory == category ? .semibold : .regular)
                        .foregroundStyle(selectedCategory == category ? .white : .primary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.15), value: selectedCategory)
    }

    // MARK: - States

    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(selectedCategory == nil ? "리그, 팀, 선수를 검색하세요" : "\(selectedCategory!.rawValue) 이름으로 검색하세요")
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
                LogoBadgeView(imageURL: league.imageURL, size: 36)
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
                LogoBadgeView(imageURL: team.imageURL, size: 36)
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
                RoleBadge(role: player.role)
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

    private func toggleFavoriteTeam(_ team: Team, league: League, isFav: Bool) {
        if isFav {
            favoriteTeams.first { $0.teamId == team.id }.map { modelContext.delete($0) }
        } else {
            guard !favoriteTeams.contains(where: { $0.teamId == team.id }) else { return }
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
