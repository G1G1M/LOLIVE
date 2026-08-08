//
//  PlayersView.swift
//  LOLIVE
//

import SwiftUI

struct PlayersView: View {
    @State private var viewModel = PlayersViewModel()

    private let roles: [(label: String, value: String)] = [
        ("TOP", "top"), ("JGL", "jungle"), ("MID", "mid"),
        ("BOT", "bottom"), ("SUP", "support")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 고정 타이틀 헤더
                HStack {
                    Text("선수")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if viewModel.isLoading {
                        LoadingView("선수 목록 불러오는 중...")
                    } else if viewModel.loadFailed {
                        ErrorRetryView { Task { await viewModel.load() } }
                    } else {
                        playerContent
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
        .task { await viewModel.load() }
    }

    // MARK: - Content

    private var playerContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    playerList
                } header: {
                    filterHeader
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Filter Header

    private var filterHeader: some View {
        VStack(spacing: 0) {
            // 검색 바
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("선수 검색", text: $viewModel.searchText)
                    .font(.subheadline)
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
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
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("전체", isSelected: viewModel.selectedRole == nil) {
                        viewModel.selectedRole = nil
                    }
                    ForEach(roles, id: \.value) { role in
                        filterChip(role.label, isSelected: viewModel.selectedRole == role.value) {
                            viewModel.selectedRole = viewModel.selectedRole == role.value ? nil : role.value
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("전체 리그", isSelected: viewModel.selectedLeagueId == nil) {
                        viewModel.selectedLeagueId = nil
                    }
                    ForEach(viewModel.leagues) { league in
                        filterChip(league.name, isSelected: viewModel.selectedLeagueId == league.id) {
                            viewModel.selectedLeagueId = viewModel.selectedLeagueId == league.id ? nil : league.id
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }

            Divider()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func filterChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        SelectableChip(isSelected: isSelected, action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }

    // MARK: - Player List

    private var playerList: some View {
        LazyVStack(spacing: 0) {
            if viewModel.filteredPlayers.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.filteredPlayers) { entry in
                    NavigationLink {
                        LeaguePlayerDetailView(player: entry.player, league: entry.league)
                    } label: {
                        playerRow(entry)
                    }
                    .buttonStyle(.plain)

                    if entry.id != viewModel.filteredPlayers.last?.id {
                        Divider().padding(.leading, 68)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(16)
    }

    private func playerRow(_ entry: PlayersViewModel.PlayerEntry) -> some View {
        HStack(spacing: 12) {
            PlayerAvatarView(imageURL: entry.player.imageURL, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.player.summonerName)
                    .font(.subheadline).fontWeight(.semibold)
                if let first = entry.player.firstName, let last = entry.player.lastName,
                   !first.isEmpty || !last.isEmpty {
                    Text("\(first) \(last)".trimmingCharacters(in: .whitespaces))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                CachedAsyncImage(url: URL(string: entry.teamImageURL ?? ""))
                    .frame(width: 20, height: 20)

                Text(entry.player.teamCode)
                    .font(.caption).foregroundStyle(.secondary)

                RoleBadge(role: entry.player.role)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var emptyState: some View {
        EmptyStateView(
            viewModel.allPlayers.isEmpty ? "선수 데이터가 없습니다" : "검색 결과가 없습니다",
            icon: "person.slash"
        )
    }
}

#Preview {
    PlayersView()
        .preferredColorScheme(.dark)
}
