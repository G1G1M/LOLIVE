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
    @State private var selectedTab: TeamTab = .roster
    @Environment(\.modelContext) private var modelContext
    @Environment(TodayViewModel.self) private var todayViewModel

    private enum TeamTab: String, CaseIterable {
        case roster  = "선수단"
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
                    fetchErrorView { Task { await viewModel.load() } }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorited ? "star.fill" : "star")
                        .foregroundStyle(isFavorited ? .yellow : .primary)
                }
            }
        }
        .task {
            viewModel.updateLeague(resolvedHomeLeague)
            await viewModel.load()
            checkFavoriteStatus()
        }
    }

    // MARK: - Header

    private var teamHeader: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                .frame(width: 60, height: 60)

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
            if viewModel.players.isEmpty {
                emptyState(icon: "person.3", message: "선수 정보가 없습니다")
            } else {
                rosterCard
            }
        case .h2h:
            if viewModel.h2hRecords.isEmpty {
                emptyState(icon: "arrow.left.arrow.right", message: "맞대결 기록이 없습니다")
            } else {
                h2hCard
            }
        case .recent:
            if viewModel.recentMatches.isEmpty {
                emptyState(icon: "calendar.badge.clock", message: "최근 경기 기록이 없습니다")
            } else {
                recentMatchesCard
            }
        }
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

    // MARK: - Error

    private func fetchErrorView(_ retry: @escaping () -> Void) -> some View {
        ErrorRetryView(retry: retry)
    }

    // MARK: - Favorite

    private func checkFavoriteStatus() {
        let code = team.code
        let descriptor = FetchDescriptor<FavoriteTeam>(predicate: #Predicate { $0.teamCode == code })
        isFavorited = (try? modelContext.fetch(descriptor))?.isEmpty == false
    }

    private func toggleFavorite() {
        let code = team.code
        let descriptor = FetchDescriptor<FavoriteTeam>(predicate: #Predicate { $0.teamCode == code })
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            existing.forEach { modelContext.delete($0) }
            isFavorited = false
        } else {
            modelContext.insert(FavoriteTeam(team: team, league: resolvedHomeLeague))
            isFavorited = true
        }
    }

    // 국제 대회 컨텍스트(MSI/Worlds)에서 즐겨찾기 시 홈 리그로 저장
    private var resolvedHomeLeague: League {
        let name = league.name.lowercased()
        let region = league.region.lowercased()
        let isIntl = name.contains("msi") || name.contains("worlds") || name.contains("월드") ||
                     region.contains("international") || region.contains("국제")
        guard isIntl else { return league }
        let allMatches = todayViewModel.completedMatches + todayViewModel.todayMatches + todayViewModel.upcomingMatches
        for match in allMatches {
            let ml = match.league.name.lowercased()
            let mr = match.league.region.lowercased()
            let isMatchIntl = ml.contains("msi") || ml.contains("worlds") || ml.contains("월드") ||
                              mr.contains("international") || mr.contains("국제")
            guard !isMatchIntl else { continue }
            if match.teamA.code.uppercased() == team.code.uppercased() ||
               match.teamB.code.uppercased() == team.code.uppercased() {
                return match.league
            }
        }
        return league
    }

    // MARK: - Roster Card

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            PlayerAvatarView(imageURL: player.imageURL, size: 40)

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

    // MARK: - H2H Card

    private var h2hCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.h2hRecords) { record in
                HStack(spacing: 12) {
                    CachedAsyncImage(url: URL(string: record.opponent.imageURL ?? ""))
                        .frame(width: 32, height: 32)

                    Text(record.opponent.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Text("\(record.wins)승 \(record.losses)패")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(record.wins > record.losses ? .primary : .secondary)

                    Text(String(format: "%.0f%%", record.winRate * 100))
                        .font(.caption).fontWeight(.bold)
                        .frame(width: 38, alignment: .trailing)
                        .foregroundStyle(record.winRate >= 0.5 ? .blue : .red)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                if record.id != viewModel.h2hRecords.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Matches Card

    private var recentMatchesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(viewModel.recentMatches.enumerated()), id: \.element.id) { idx, match in
                let isTeamA  = match.teamA.id == team.id || match.teamA.code == team.code
                let myScore  = isTeamA ? match.scoreA : match.scoreB
                let oppScore = isTeamA ? match.scoreB : match.scoreA
                let opponent = isTeamA ? match.teamB : match.teamA
                let won      = myScore > oppScore

                NavigationLink(destination: MatchDetailView(match: match)) {
                    recentMatchRow(opponent: opponent, myScore: myScore,
                                   oppScore: oppScore, won: won, date: match.startTime)
                }
                .buttonStyle(.plain)

                if idx < viewModel.recentMatches.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func recentMatchRow(opponent: Team, myScore: Int, oppScore: Int,
                                won: Bool, date: Date) -> some View {
        HStack(spacing: 12) {
            Text(won ? "W" : "L")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(won ? Color.blue : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            CachedAsyncImage(url: URL(string: opponent.imageURL ?? ""))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(opponent.name)")
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
                Text(date.formatted(.dateTime
                    .month(.abbreviated).day()
                    .locale(Locale(identifier: "ko_KR"))))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(myScore) - \(oppScore)")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(won ? .primary : .secondary)

            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func roleLabel(_ role: String) -> String { RoleStyle.label(role) }
    private func roleColor(_ role: String) -> Color  { RoleStyle.color(role) }
}
