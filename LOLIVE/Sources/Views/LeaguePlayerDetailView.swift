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
    @Environment(\.modelContext) private var modelContext

    init(player: Player, league: League) {
        self.player = player
        self.league = league
        self._viewModel = State(initialValue: LeaguePlayerDetailViewModel(player: player, league: league))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    profileCard

                    SeasonStatsView(player: player, league: league)

                    if viewModel.isLoadingStats {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("통계 불러오는 중...")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        if !viewModel.championStats.isEmpty {
                            championCard
                        }
                        if !viewModel.recentResults.isEmpty {
                            recentMatchesCard
                        }
                    }
                }
                .padding(16)
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

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: player.imageURL ?? ""))
                .frame(width: 72, height: 72)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(player.summonerName)
                    .font(.title3).fontWeight(.bold)

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
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Champion Stats Card

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

            // 컬럼 헤더
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
            Text("최근 경기")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

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

    private func roleLabel(_ role: String) -> String {
        switch role.lowercased() {
        case "top":              return "TOP"
        case "jungle":           return "JGL"
        case "mid":              return "MID"
        case "bottom", "bot":    return "BOT"
        case "support":          return "SUP"
        default:                 return role.uppercased()
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role.lowercased() {
        case "top":              return .orange
        case "jungle":           return .green
        case "mid":              return .blue
        case "bottom", "bot":    return .red
        case "support":          return .purple
        default:                 return .secondary
        }
    }
}
