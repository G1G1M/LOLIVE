//
//  LeaguePlayerDetailView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct LeaguePlayerDetailView: View {
    let player: Player
    let league: League

    @State var viewModel: LeaguePlayerDetailViewModel
    @State var isFavorited = false
    @State private var selectedTab: PlayerTab = .stats
    @State var selectedChampion: LeaguePlayerDetailViewModel.ChampionStat? = nil
    @State var showStatsDetail = false
    @Environment(\.modelContext) var modelContext

    private enum PlayerTab: String, CaseIterable {
        case stats     = "통계"
        case champions = "챔피언풀"
        case recent    = "최근경기"
    }

    init(player: Player, league: League) {
        self.player = player
        self.league = league
        self._viewModel = State(initialValue: LeaguePlayerDetailViewModel(player: player, league: league))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                playerHeader
                Divider()
                tabBar
                Divider()

                ScrollView {
                    tabContent
                        .padding(16)
                }
                // "챔피언풀"/"통계" 탭은 데이터가 늦게 도착해 로딩→콘텐츠로 크기가 크게 바뀌는데,
                // 탭 전환에 크로스페이드를 걸면 그 크기 변화까지 같이 묶여 어색해 보임(LeagueDetailView와
                // 동일 원인) — 애니메이션을 꺼서 즉시 전환되도록 통일
                .transaction(value: selectedTab) { $0.disablesAnimations = true }
            }
        }
        .navigationTitle(player.summonerName)
        .navigationBarTitleDisplayMode(.inline)
        // Match.self는 여기서 등록 안 함 — TeamDetailView와 동일한 이유(그쪽 주석 참고).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .foregroundStyle(isFavorited ? .yellow : .secondary)
                }
                .accessibilityLabel(isFavorited ? "즐겨찾기 해제" : "즐겨찾기 추가")
            }
        }
        .task {
            await viewModel.load()
            checkFavoriteStatus()
        }
        .sheet(item: $selectedChampion) { stat in
            ChampionDetailSheet(stat: stat)
                .sheetGrabber()
        }
        .sheet(isPresented: $showStatsDetail) {
            if let oeStats = viewModel.playerOEStats {
                PlayerStatsDetailSheet(playerName: player.summonerName, stats: oeStats)
                    .sheetGrabber()
            }
        }
    }

    // MARK: - Header

    private var playerHeader: some View {
        HStack(spacing: 16) {
            PlayerAvatarView(imageURL: player.imageURL, size: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(player.summonerName)
                    .font(.title2).fontWeight(.bold)

                if let first = player.firstName, let last = player.lastName,
                   !first.isEmpty || !last.isEmpty {
                    Text("\(first) \(last)".trimmingCharacters(in: .whitespaces))
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(player.teamCode)
                        .font(.caption).foregroundStyle(.secondary)

                    RoleBadge(role: player.role)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(.systemBackground))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PlayerTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .stats:
            if viewModel.availableSeasons.count > 1 {
                SeasonPicker(seasons: viewModel.availableSeasons, selectedId: viewModel.selectedSeasonId) {
                    viewModel.selectSeason($0)
                }
            }
            SeasonStatsView(
                stats: viewModel.effectiveSeasonStats, isLoading: viewModel.isLoadingStats,
                onTapDetail: viewModel.playerOEStats != nil ? { showStatsDetail = true } : nil
            )
            if !viewModel.recentResults.isEmpty {
                recentFormCard
            }

        case .champions:
            if viewModel.isLoadingStats && viewModel.championStats.isEmpty {
                LoadingView("챔피언 통계 불러오는 중...")
            } else if viewModel.championStats.isEmpty {
                EmptyStateView("챔피언 통계가 없습니다", icon: "gamecontroller")
            } else {
                championCard
            }

        case .recent:
            if viewModel.recentResults.isEmpty && viewModel.isLoadingStats {
                LoadingView("최근 경기 불러오는 중...")
            } else if viewModel.recentResults.isEmpty {
                EmptyStateView("최근 경기 기록이 없습니다", icon: "calendar.badge.clock")
            } else {
                RecentMatchesCard(items: recentMatchItems)
            }
        }
    }
}
