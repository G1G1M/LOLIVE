//
//  TeamDetailView.swift
//  LOLIVE
//
//  팀 상세 화면의 뼈대 — 헤더 / 탭 바 / 탭별 내용 분기까지만 담당한다.
//  각 탭의 실제 카드는 탭별 extension 파일로 분리:
//    +Roster   — 선수단
//    +Stats    — 시즌 스탯 카드
//    +H2H      — 상대 전적, 최근경기
//    +Favorite — 즐겨찾기 토글과 홈 리그 판별
//

import SwiftUI

struct TeamDetailView: View {
    let team: Team
    let league: League
    var standing: Standing? = nil

    @State var viewModel: TeamDetailViewModel
    @State var isFavorited = false
    @State private var selectedTab: TeamTab = .roster
    @State var showStatsDetail = false
    @Environment(\.modelContext) var modelContext
    @Environment(TodayViewModel.self) var todayViewModel

    private enum TeamTab: String, CaseIterable {
        case roster  = "선수단"
        case stats   = "스탯"
        case h2h     = "상대 전적"
        case recent  = "최근경기"
    }

    init(team: Team, league: League, standing: Standing? = nil) {
        self.team = team
        self.league = league
        self.standing = standing
        self._viewModel = State(initialValue: TeamDetailViewModel(team: team, league: league))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                teamHeader
                Divider()
                tabBar
                Divider()

                if viewModel.isLoading {
                    LoadingView()
                } else if viewModel.loadFailed {
                    ErrorRetryView { Task { await viewModel.load() } }
                } else {
                    ScrollView {
                        tabContent
                            .padding(16)
                            .animation(.easeInOut(duration: 0.15), value: selectedTab)
                    }
                }
            }
        }
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        // Match.self는 여기서 등록 안 함 — 각 탭 루트(TodayView 등)에서 한 번만 등록.
        // 이 화면이 LeagueDetailView 스택에 중첩될 때 같은 타입이 두 번 등록되는 걸 막기 위함
        // (자세한 이유는 LeagueDetailView.swift 주석 참고).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .foregroundStyle(isFavorited ? .yellow : .secondary)
                }
            }
        }
        .task {
            viewModel.updateLeague(resolvedHomeLeague)
            viewModel.setCrossLeagueMatches(
                todayViewModel.completedMatches + todayViewModel.todayMatches + todayViewModel.upcomingMatches
            )
            await viewModel.load()
            checkFavoriteStatus()
        }
        .sheet(isPresented: $showStatsDetail) {
            if let stats = viewModel.teamStats {
                TeamStatsDetailSheet(teamName: team.name, stats: stats)
                    .sheetGrabber()
            }
        }
    }

    // MARK: - Header

    private var teamHeader: some View {
        HStack(spacing: 16) {
            LogoBadgeView(imageURL: team.imageURL, size: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.title2).fontWeight(.bold)
                Text(team.code)
                    .font(.subheadline).foregroundStyle(.secondary)

                if let s = standing {
                    HStack(spacing: 10) {
                        Label("#\(s.rank)", systemImage: "trophy")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(s.wins)승 \(s.losses)패")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "%.0f%%", s.winRate * 100))
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(s.winRate >= 0.5 ? Color.blue : Color.secondary)
                    }
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
            ForEach(TeamTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
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
        case .roster:
            if viewModel.isLoading && viewModel.players.isEmpty {
                LoadingView("선수단 불러오는 중...")
            } else if viewModel.players.isEmpty {
                EmptyStateView("선수 정보가 없습니다", icon: "person.3")
            } else {
                rosterCard
            }
        case .stats:
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.availableSeasons.count > 1 {
                    SeasonPicker(seasons: viewModel.availableSeasons, selectedId: viewModel.selectedSeasonId) {
                        viewModel.selectSeason($0)
                    }
                }
                if viewModel.isLoadingTeamStats && viewModel.teamStats == nil {
                    LoadingView("팀 스탯 불러오는 중...")
                } else if let stats = viewModel.teamStats {
                    teamStatsCard(stats)
                } else {
                    EmptyStateView("팀 스탯이 없습니다", icon: "chart.bar.xaxis")
                }
            }
        case .h2h:
            if viewModel.isLoading && viewModel.h2hRecords.isEmpty {
                LoadingView("상대 전적 불러오는 중...")
            } else if viewModel.h2hRecords.isEmpty {
                EmptyStateView("맞대결 기록이 없습니다", icon: "arrow.left.arrow.right")
            } else {
                h2hCard
            }
        case .recent:
            if viewModel.isLoading && viewModel.recentMatches.isEmpty {
                LoadingView("최근 경기 불러오는 중...")
            } else if viewModel.recentMatches.isEmpty {
                EmptyStateView("최근 경기 기록이 없습니다", icon: "calendar.badge.clock")
            } else {
                RecentMatchesCard(items: recentMatchItems)
            }
        }
    }
}
