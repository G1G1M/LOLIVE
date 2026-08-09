//
//  PlayersView.swift
//  LOLIVE
//

import SwiftUI

struct PlayersView: View {
    @State private var viewModel = PlayersViewModel()
    @FocusState private var isSearchFocused: Bool

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

                searchBar

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
            // 진짜 네이티브 .searchable(iOS 26 리퀴드 글래스 자동 적용)은 시스템 타이틀에만
            // 붙어서, 커스텀 타이틀(오늘의 경기/순위와 동일 스타일)을 쓰면 위쪽 여백이 iOS 26
            // 새 네비게이션 바 디자인 때문에 훨씬 커진다(실측 확인). 커스텀 검색창에
            // .glassEffect만 입혀서 겉모습은 동일하게, 여백은 타이트하게 유지한다.
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

    // MARK: - Search Bar

    private var searchBar: some View {
        GlassFieldBackground {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("선수 검색", text: $viewModel.searchText)
                    .font(.subheadline)
                    .focused($isSearchFocused)
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
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

    @ViewBuilder
    private var filterHeader: some View {
        if isSearchFocused {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    roleMenu
                    leagueMenu
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var roleMenu: some View {
        Menu {
            Button {
                viewModel.selectedRole = nil
            } label: {
                if viewModel.selectedRole == nil { Label("전체", systemImage: "checkmark") }
                else { Text("전체") }
            }
            ForEach(roles, id: \.value) { role in
                Button {
                    viewModel.selectedRole = role.value
                } label: {
                    if viewModel.selectedRole == role.value { Label(role.label, systemImage: "checkmark") }
                    else { Text(role.label) }
                }
            }
        } label: {
            MenuFilterLabel {
                Text(roles.first { $0.value == viewModel.selectedRole }?.label ?? "포지션")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .tint(Color(.label))
    }

    private var leagueMenu: some View {
        Menu {
            Button {
                viewModel.selectedLeagueId = nil
            } label: {
                if viewModel.selectedLeagueId == nil { Label("전체 리그", systemImage: "checkmark") }
                else { Text("전체 리그") }
            }
            ForEach(viewModel.leagues) { league in
                Button {
                    viewModel.selectedLeagueId = league.id
                } label: {
                    if viewModel.selectedLeagueId == league.id { Label(league.name, systemImage: "checkmark") }
                    else { Text(league.name) }
                }
            }
        } label: {
            MenuFilterLabel {
                Text(viewModel.leagues.first { $0.id == viewModel.selectedLeagueId }?.name ?? "리그")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .tint(Color(.label))
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
