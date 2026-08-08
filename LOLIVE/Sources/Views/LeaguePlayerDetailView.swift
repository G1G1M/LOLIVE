//
//  LeaguePlayerDetailView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct LeaguePlayerDetailView: View {
    let player: Player
    let league: League

    @State private var viewModel: LeaguePlayerDetailViewModel
    @State private var isFavorited = false
    @State private var selectedTab: PlayerTab = .stats
    @State private var selectedChampion: LeaguePlayerDetailViewModel.ChampionStat? = nil
    @Environment(\.modelContext) private var modelContext

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
            }
        }
        .task {
            await viewModel.load()
            checkFavoriteStatus()
        }
        .sheet(item: $selectedChampion) { stat in
            ChampionDetailSheet(stat: stat)
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
            SeasonStatsView(stats: viewModel.seasonStats, isLoading: viewModel.isLoadingStats)
            if !viewModel.recentResults.isEmpty {
                recentFormCard
            }

        case .champions:
            if viewModel.isLoadingStats && viewModel.championStats.isEmpty {
                LoadingView("챔피언 통계 불러오는 중...")
                    .frame(minHeight: 120)
            } else if viewModel.championStats.isEmpty {
                EmptyStateView("챔피언 통계가 없습니다", icon: "gamecontroller")
            } else {
                championCard
            }

        case .recent:
            if viewModel.recentResults.isEmpty && viewModel.isLoadingStats {
                LoadingView("최근 경기 불러오는 중...")
                    .frame(minHeight: 120)
            } else if viewModel.recentResults.isEmpty {
                EmptyStateView("최근 경기 기록이 없습니다", icon: "calendar.badge.clock")
            } else {
                RecentMatchesCard(items: recentMatchItems)
            }
        }
    }

    // MARK: - Favorite

    private func checkFavoriteStatus() {
        let id = player.id
        let descriptor = FetchDescriptor<FavoritePlayer>(predicate: #Predicate { $0.playerId == id })
        isFavorited = (try? modelContext.fetch(descriptor))?.isEmpty == false
    }

    private func toggleFavorite() {
        let id = player.id
        let descriptor = FetchDescriptor<FavoritePlayer>(predicate: #Predicate { $0.playerId == id })
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            existing.forEach { modelContext.delete($0) }
            isFavorited = false
        } else {
            modelContext.insert(FavoritePlayer(player: player, league: league))
            isFavorited = true
        }
    }

    // MARK: - Recent Form Card

    private var recentFormCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 폼")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(viewModel.recentResults.prefix(5)) { result in
                    VStack(spacing: 4) {
                        Text(result.won ? "W" : "L")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(result.won ? Color.blue : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(result.date.formatted(.dateTime
                            .month(.twoDigits).day()
                            .locale(Locale(identifier: "ko_KR"))))
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()

                let wins = viewModel.recentResults.prefix(5).filter { $0.won }.count
                let total = min(viewModel.recentResults.count, 5)
                Text("\(wins)승 \(total - wins)패")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Champion Card

    private var championCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("챔피언 풀")
                    .font(.headline)
                Spacer()
                Text("최근 \(viewModel.recentResults.count)경기 기준")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            HStack(spacing: 0) {
                Text("#").frame(width: 24, alignment: .center)
                Text("챔피언").frame(maxWidth: .infinity, alignment: .leading)
                Text("게임").frame(width: 38, alignment: .center)
                Text("승률").frame(width: 50, alignment: .center)
                Text("KDA").frame(width: 54, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider().padding(.horizontal, 16)

            ForEach(Array(viewModel.championStats.enumerated()), id: \.element.id) { idx, stat in
                Button {
                    selectedChampion = stat
                } label: {
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .center)

                        HStack(spacing: 8) {
                            ChampionImageView(championId: stat.championId, size: 30)
                            Text(stat.championId)
                                .font(.subheadline).fontWeight(.medium)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(stat.games)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .center)

                        Text(String(format: "%.0f%%", stat.winRate * 100))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(winRateColor(stat.winRate))
                            .frame(width: 50, alignment: .center)

                        Text(String(format: "%.2f", stat.kda))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(kdaColor(stat.kda))
                            .frame(width: 54, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if idx < viewModel.championStats.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func winRateColor(_ rate: Double) -> Color {
        if rate >= 0.6 { return .blue }
        if rate < 0.4  { return .secondary }
        return Color(.label)
    }

    private func kdaColor(_ kda: Double) -> Color {
        if kda >= 4.0 { return .blue }
        if kda >= 2.0 { return Color(.label) }
        return .secondary
    }

    // MARK: - Recent Matches Card

    private var recentMatchItems: [RecentMatchesCard.Item] {
        viewModel.recentResults.map { result in
            RecentMatchesCard.Item(id: result.id, match: result.match, opponent: result.opponent,
                                    myScore: result.myScore, oppScore: result.oppScore,
                                    won: result.won, date: result.date)
        }
    }

    // MARK: - Helpers

}
