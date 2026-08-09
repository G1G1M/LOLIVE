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

    // MARK: - Error

    private func fetchErrorView(_ retry: @escaping () -> Void) -> some View {
        ErrorRetryView(retry: retry)
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
            modelContext.insert(FavoriteTeam(team: team, league: resolvedHomeLeague))
            isFavorited = true
        }
    }

    // 국제 대회(MSI/Worlds)·국내 컵 대회(케스파컵 등) 컨텍스트에서 즐겨찾기 시 홈 리그로 저장.
    // 이런 대회는 팀의 정규 소속 리그가 아니라 별도로 열리는 대회라, 팀 상세 진입 시에도
    // 항상 홈 리그(LCK 등) 기준 선수단·최근경기·즐겨찾기 소속 리그를 사용해야 한다.
    private var resolvedHomeLeague: League {
        guard Self.isSpecialTournament(league) else { return league }
        let allMatches = todayViewModel.completedMatches + todayViewModel.todayMatches + todayViewModel.upcomingMatches
        for match in allMatches {
            guard !Self.isSpecialTournament(match.league) else { continue }
            if match.teamA.code.uppercased() == team.code.uppercased() ||
               match.teamB.code.uppercased() == team.code.uppercased() {
                return match.league
            }
        }
        return league
    }

    /// 팀의 정규 소속 리그가 아니라 별도로 열리는 대회인지 판별.
    /// MSI/Worlds 같은 국제 대회뿐 아니라 케스파컵처럼 지역이 "한국"으로 찍히는
    /// 국내 컵 대회도 포함 — region만으로는 못 걸러서 이름/슬러그도 함께 확인한다.
    private static func isSpecialTournament(_ league: League) -> Bool {
        let name = league.name.lowercased()
        let slug = league.slug.lowercased()
        let region = league.region.lowercased()
        return name.contains("msi") || name.contains("worlds") || name.contains("월드") ||
               region.contains("international") || region.contains("국제") ||
               name.contains("kespa") || slug.contains("kespa")
    }

    // MARK: - Roster Card

    /// Riot getTeams 응답엔 주전/후보 구분이 없어 포지션당 여러 명이 그대로 옴(예: T1 BOT 4명).
    /// viewModel.currentStarterNames(최근 경기 실제 출전 명단)로 구할 수 있으면 주전을 먼저,
    /// 나머지는 "기타 등록 선수"로 분리 표시. 못 구했으면(원정경기 없음/API 실패) 기존처럼 전체 나열.
    private func isCurrentStarter(_ player: Player) -> Bool {
        viewModel.currentStarterNames.contains(player.summonerName.trimmingCharacters(in: .whitespaces).lowercased())
    }

    private var rosterCard: some View {
        let starters = viewModel.currentStarterNames.isEmpty
            ? viewModel.players
            : viewModel.players.filter(isCurrentStarter)
        let bench = viewModel.currentStarterNames.isEmpty
            ? []
            : viewModel.players.filter { !isCurrentStarter($0) }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(starters) { player in
                NavigationLink {
                    LeaguePlayerDetailView(player: player, league: league)
                } label: {
                    playerRow(player)
                }
                .buttonStyle(.plain)
                if player.id != starters.last?.id || !bench.isEmpty {
                    Divider().padding(.leading, 68)
                }
            }

            if !bench.isEmpty {
                Text("기타 등록 선수")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)

                ForEach(bench) { player in
                    NavigationLink {
                        LeaguePlayerDetailView(player: player, league: league)
                    } label: {
                        playerRow(player)
                    }
                    .buttonStyle(.plain)
                    if player.id != bench.last?.id {
                        Divider().padding(.leading, 68)
                    }
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

            RoleBadge(role: player.role)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - H2H Card

    private var h2hCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.h2hRecords) { record in
                HStack(spacing: 12) {
                    LogoBadgeView(imageURL: record.opponent.imageURL, size: 36)

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
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Matches Card

    private var recentMatchItems: [RecentMatchesCard.Item] {
        viewModel.recentMatches.map { match in
            let isTeamA  = match.teamA.id == team.id || match.teamA.code == team.code
            let myScore  = isTeamA ? match.scoreA : match.scoreB
            let oppScore = isTeamA ? match.scoreB : match.scoreA
            let opponent = isTeamA ? match.teamB : match.teamA
            return RecentMatchesCard.Item(id: match.id, match: match, opponent: opponent,
                                           myScore: myScore, oppScore: oppScore,
                                           won: myScore > oppScore, date: match.startTime)
        }
    }

}
