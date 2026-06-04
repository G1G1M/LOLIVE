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
                        .animation(.easeInOut(duration: 0.15), value: selectedTab)
                }
            }
        }
        .navigationTitle(player.summonerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .foregroundStyle(isFavorited ? .yellow : .primary)
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
            CachedAsyncImage(url: URL(string: player.imageURL ?? ""))
                .frame(width: 60, height: 60)
                .clipShape(Circle())

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

                    Text(roleLabel(player.role))
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(roleColor(player.role).opacity(0.2))
                        .foregroundStyle(roleColor(player.role))
                        .clipShape(Capsule())
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
        case .stats:
            SeasonStatsView(stats: viewModel.seasonStats, isLoading: viewModel.isLoadingStats)
            if !viewModel.recentResults.isEmpty {
                recentFormCard
            }

        case .champions:
            if viewModel.isLoadingStats && viewModel.championStats.isEmpty {
                loadingView(message: "챔피언 통계 불러오는 중...")
            } else if viewModel.championStats.isEmpty {
                emptyState(icon: "gamecontroller", message: "챔피언 통계가 없습니다")
            } else {
                championCard
            }

        case .recent:
            if viewModel.recentResults.isEmpty && viewModel.isLoadingStats {
                loadingView(message: "최근 경기 불러오는 중...")
            } else if viewModel.recentResults.isEmpty {
                emptyState(icon: "calendar.badge.clock", message: "최근 경기 기록이 없습니다")
            } else {
                recentMatchesCard
            }
        }
    }

    private func loadingView(message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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

    private var recentMatchesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.recentResults) { result in
                NavigationLink(destination: MatchDetailView(match: result.match)) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(result.won ? Color.blue : Color.red)
                            .frame(width: 3, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("vs \(result.opponent.name)")
                                .font(.subheadline).fontWeight(.medium)
                                .lineLimit(1)
                            Text(result.date, style: .date)
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(result.myScore)-\(result.oppScore)")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(result.won ? .primary : .secondary)

                        Text(result.won ? "승" : "패")
                            .font(.caption2).fontWeight(.bold)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((result.won ? Color.blue : Color.red).opacity(0.15))
                            .foregroundStyle(result.won ? .blue : .red)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if result.id != viewModel.recentResults.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func roleLabel(_ role: String) -> String { RoleStyle.label(role) }
    private func roleColor(_ role: String) -> Color  { RoleStyle.color(role) }
}

// MARK: - Champion Detail Sheet

private struct ChampionDetailSheet: View {
    let stat: LeaguePlayerDetailViewModel.ChampionStat
    @Environment(\.dismiss) private var dismiss

    private struct CumulativePoint: Identifiable {
        let id: Int
        let gameNumber: Int
        let winRate: Double
        let won: Bool
    }

    private var cumulativePoints: [CumulativePoint] {
        var wins = 0
        return stat.entries.enumerated().map { idx, entry in
            if entry.won { wins += 1 }
            return CumulativePoint(id: idx, gameNumber: idx + 1,
                                   winRate: Double(wins) / Double(idx + 1),
                                   won: entry.won)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        if cumulativePoints.count >= 2 {
                            chartCard
                        }
                        gameListCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(stat.championId)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ChampionImageView(championId: stat.championId, size: 28)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        HStack(spacing: 0) {
            statCell("\(stat.games)", label: "게임")
            Divider().frame(height: 44)
            statCell(String(format: "%.0f%%", stat.winRate * 100),
                     label: "승률", color: winRateColor(stat.winRate))
            Divider().frame(height: 44)
            statCell(String(format: "%.2f", stat.kda),
                     label: "KDA", color: kdaColor(stat.kda))
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statCell(_ value: String, label: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("승률 추이")
                .font(.headline)

            winRateChart
                .frame(height: 200)

            resultDotsRow
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var winRateChart: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 50% 기준선
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
                    .offset(y: geo.size.height * 0.5)

                // 승률 선
                if cumulativePoints.count >= 2 {
                    Path { path in
                        for (i, pt) in cumulativePoints.enumerated() {
                            let x = xPos(i, total: cumulativePoints.count, width: geo.size.width)
                            let y = geo.size.height * (1.0 - pt.winRate)
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else       { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }

                // 점
                ForEach(Array(cumulativePoints.enumerated()), id: \.offset) { i, pt in
                    let x = xPos(i, total: cumulativePoints.count, width: geo.size.width)
                    let y = geo.size.height * (1.0 - pt.winRate)
                    Circle()
                        .fill(pt.won ? Color.blue : Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: x - 4, y: y - 4)
                }

                // Y 축 레이블
                VStack {
                    Text("100%").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("50%").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("0%").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(height: geo.size.height)
            }
        }
    }

    private func xPos(_ index: Int, total: Int, width: CGFloat) -> CGFloat {
        guard total > 1 else { return width / 2 }
        return CGFloat(index) / CGFloat(total - 1) * width
    }

    private var resultDotsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(stat.entries.enumerated()), id: \.offset) { idx, entry in
                    VStack(spacing: 2) {
                        Text(entry.won ? "W" : "L")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(entry.won ? Color.blue : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("\(idx + 1)")
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: Game List

    private var gameListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("게임 기록")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().padding(.horizontal, 16)
            ForEach(Array(stat.entries.enumerated()), id: \.offset) { idx, entry in
                HStack(spacing: 12) {
                    Text(entry.won ? "W" : "L")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(entry.won ? Color.blue : Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text("게임 \(idx + 1)")
                        .font(.subheadline)

                    Spacer()

                    if let d = entry.date {
                        Text(d.formatted(.dateTime.month(.abbreviated).day()
                            .locale(Locale(identifier: "ko_KR"))))
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }

                    Text("\(entry.kills)/\(entry.deaths)/\(entry.assists)")
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                if idx < stat.entries.count - 1 {
                    Divider().padding(.leading, 50)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Helpers

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
}
