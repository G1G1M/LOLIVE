//
//  PlayersView.swift
//  LOLIVE
//

import SwiftUI

struct PlayersView: View {
    @State private var viewModel = PlayersViewModel()
    @State private var isSearchPresented = false

    private let roles: [(label: String, value: String)] = [
        ("TOP", "top"), ("JGL", "jungle"), ("MID", "mid"),
        ("BOT", "bottom"), ("SUP", "support")
    ]

    var body: some View {
        NavigationStack {
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
            // 진짜 네이티브 .searchable(리퀴드 글래스 자동 적용)을 쓰려면 시스템 타이틀이
            // 필요하다 — SwiftUI 구조상 검색창은 항상 네비게이션 바에만 붙기 때문에,
            // 네비게이션 바를 숨기고 커스텀 타이틀을 쓰면 검색창 자체가 안 뜬다(실측 확인).
            .navigationTitle("선수")
            .searchable(
                text: $viewModel.searchText, isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always), prompt: "선수 검색"
            )
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

    @ViewBuilder
    private var filterHeader: some View {
        if isSearchPresented {
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
