//
//  TeamDetailView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct TeamDetailView: View {
    let team: Team
    let league: League
    var standing: Standing? = nil

    @State private var viewModel: TeamDetailViewModel
    @State private var isFavorited = false
    @Environment(\.modelContext) private var modelContext

    init(team: Team, league: League, standing: Standing? = nil) {
        self.team = team
        self.league = league
        self.standing = standing
        self._viewModel = State(initialValue: TeamDetailViewModel(team: team, league: league))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("불러오는 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        if !viewModel.players.isEmpty {
                            rosterCard
                        }
                        if !viewModel.recentMatches.isEmpty {
                            recentMatchesCard
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(team.name)
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
        let id = team.id
        let descriptor = FetchDescriptor<FavoriteTeam>(predicate: #Predicate { $0.teamId == id })
        isFavorited = (try? modelContext.fetch(descriptor))?.isEmpty == false
    }

    private func toggleFavorite() {
        let id = team.id
        let descriptor = FetchDescriptor<FavoriteTeam>(predicate: #Predicate { $0.teamId == id })
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            existing.forEach { modelContext.delete($0) }
            isFavorited = false
        } else {
            modelContext.insert(FavoriteTeam(team: team, league: league))
            isFavorited = true
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(team.name)
                    .font(.title3).fontWeight(.bold)
                Text(team.code)
                    .font(.subheadline).foregroundStyle(.secondary)

                if let s = standing {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy")
                                .font(.caption)
                            Text("#\(s.rank)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)

                        Text("\(s.wins)승 \(s.losses)패")
                            .font(.caption).foregroundStyle(.secondary)

                        Text(String(format: "%.0f%%", s.winRate * 100))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Roster Card

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("선수단")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            ForEach(viewModel.players) { player in
                NavigationLink {
                    LeaguePlayerDetailView(player: player, league: league)
                } label: {
                    playerRow(player)
                }
                .buttonStyle(.plain)
                if player.id != viewModel.players.last?.id {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerRow(_ player: Player) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: player.imageURL ?? ""))
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(player.summonerName)
                    .font(.subheadline).fontWeight(.semibold)
                if let first = player.firstName, let last = player.lastName,
                   !first.isEmpty || !last.isEmpty {
                    Text("\(first) \(last)".trimmingCharacters(in: .whitespaces))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(roleLabel(player.role))
                .font(.caption2).fontWeight(.bold)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(roleColor(player.role).opacity(0.2))
                .foregroundStyle(roleColor(player.role))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Recent Matches Card

    private var recentMatchesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("최근 경기")
                .font(.headline)
                .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            ForEach(viewModel.recentMatches) { match in
                let isTeamA = match.teamA.id == team.id || match.teamA.code == team.code
                let myScore  = isTeamA ? match.scoreA : match.scoreB
                let oppScore = isTeamA ? match.scoreB : match.scoreA
                let opponent = isTeamA ? match.teamB : match.teamA
                let won = myScore > oppScore

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(won ? Color.blue : Color.red)
                        .frame(width: 3, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("vs \(opponent.name)")
                            .font(.subheadline).fontWeight(.medium)
                            .lineLimit(1)
                        Text(match.startTime, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(myScore)-\(oppScore)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(won ? .primary : .secondary)

                    Text(won ? "승" : "패")
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((won ? Color.blue : Color.red).opacity(0.15))
                        .foregroundStyle(won ? .blue : .red)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                if match.id != viewModel.recentMatches.last?.id {
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
