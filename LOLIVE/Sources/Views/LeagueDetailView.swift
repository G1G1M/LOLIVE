//
//  LeagueDetailView.swift
//  LOLIVE
//

import SwiftUI

struct LeagueDetailView: View {
    let league: League

    @State private var viewModel: LeagueDetailViewModel

    init(league: League) {
        self.league = league
        self._viewModel = State(initialValue: LeagueDetailViewModel(league: league))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView("불러오는 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    tabContent
                }
            }
        }
        .navigationTitle(league.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .navigationDestination(for: Team.self) { team in
            TeamDetailView(
                team: team,
                league: league,
                standing: viewModel.standings.first { $0.team.id == team.id }
            )
        }
        .navigationDestination(for: Player.self) { player in
            LeaguePlayerDetailView(player: player, league: league)
        }
        .task { await viewModel.load() }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(LeagueDetailViewModel.Tab.allCases, id: \.self) { tab in
                Button {
                    viewModel.selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.title)
                            .font(.subheadline)
                            .fontWeight(viewModel.selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(viewModel.selectedTab == tab ? .primary : .secondary)
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .standings: standingsContent
        case .schedule:  scheduleContent
        case .teams:     teamsContent
        case .players:   playersContent
        }
    }

    // MARK: - 일정 (래퍼: 토글 + 목록/브라켓 전환)

    private var scheduleContent: some View {
        VStack(spacing: 0) {
            if viewModel.isBracketAvailable {
                scheduleToggle
                Divider()
            }
            if viewModel.showBracket {
                bracketContent
            } else {
                scheduleListContent
            }
        }
    }

    private var scheduleToggle: some View {
        HStack(spacing: 8) {
            scheduleToggleButton(title: "목록", sf: "list.bullet", selected: !viewModel.showBracket) {
                viewModel.showBracket = false
            }
            scheduleToggleButton(title: "브라켓", sf: "bracket.wide", selected: viewModel.showBracket) {
                viewModel.showBracket = true
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    private func scheduleToggleButton(title: String, sf: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: sf).font(.system(size: 12))
                Text(title).font(.subheadline).fontWeight(selected ? .semibold : .regular)
            }
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 브라켓 뷰

    private var bracketContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(viewModel.bracketRounds.enumerated()), id: \.element.id) { idx, round in
                    bracketRoundColumn(round)

                    if idx < viewModel.bracketRounds.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 36)
                            .frame(width: 20)
                    }
                }
            }
            .padding(16)
        }
    }

    private func bracketRoundColumn(_ round: LeagueDetailViewModel.BracketRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(round.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(round.matches) { match in
                    bracketMatchCard(match)
                }
            }
        }
        .frame(width: 184)
    }

    private func bracketMatchCard(_ match: Match) -> some View {
        NavigationLink(value: match) {
            VStack(spacing: 0) {
                bracketTeamRow(
                    team: match.teamA, score: match.scoreA,
                    won: match.state == .completed && match.scoreA > match.scoreB,
                    state: match.state
                )
                Divider().padding(.horizontal, 12)
                bracketTeamRow(
                    team: match.teamB, score: match.scoreB,
                    won: match.state == .completed && match.scoreB > match.scoreA,
                    state: match.state
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func bracketTeamRow(team: Team, score: Int, won: Bool, state: MatchState) -> some View {
        HStack(spacing: 8) {
            CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                .frame(width: 20, height: 20)
            Text(team.code)
                .font(.system(size: 13, weight: won ? .bold : .regular))
                .foregroundStyle(won ? Color(.label) : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if state == .completed {
                Text("\(score)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(won ? Color(.label) : .secondary)
                    .frame(width: 18, alignment: .trailing)
            } else {
                Text("-")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(won ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // MARK: - 순위

    private var standingsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.standings.isEmpty {
                    emptyState("순위 데이터를 불러올 수 없습니다")
                } else {
                    standingsHeader
                    ForEach(viewModel.standings) { standing in
                        standingRow(standing)
                        if standing.id != viewModel.standings.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(16)
        }
    }

    private var standingsHeader: some View {
        HStack {
            Text("#")
                .frame(width: 32, alignment: .center)
                .foregroundStyle(.secondary)
            Text("팀")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Text("W")
                    .foregroundStyle(.blue)
                    .frame(width: 22, alignment: .center)
                Text("-")
                    .foregroundStyle(.secondary)
                    .frame(width: 10, alignment: .center)
                Text("L")
                    .foregroundStyle(.red)
                    .frame(width: 22, alignment: .center)
            }
            .frame(width: 54)
            Text("GD")
                .frame(width: 44, alignment: .center)
                .foregroundStyle(.secondary)
            Text("Win%")
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func standingRow(_ standing: Standing) -> some View {
        NavigationLink(value: standing.team) {
            HStack(spacing: 0) {
                Text("\(standing.rank)")
                    .font(.system(size: 14, weight: standing.rank <= 3 ? .bold : .regular))
                    .foregroundStyle(rankColor(standing.rank))
                    .frame(width: 32, alignment: .center)

                HStack(spacing: 10) {
                    CachedAsyncImage(url: URL(string: standing.team.imageURL ?? ""))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(standing.team.name)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Text(standing.team.code)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    Text("\(standing.wins)")
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                        .frame(width: 22, alignment: .center)
                    Text("-")
                        .foregroundStyle(.secondary)
                        .frame(width: 10, alignment: .center)
                    Text("\(standing.losses)")
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .frame(width: 22, alignment: .center)
                }
                .font(.system(size: 13, weight: .medium))
                .frame(width: 54)

                Text(gdString(standing.gameDiff))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(.label))
                    .frame(width: 44, alignment: .center)

                Text(String(format: "%.0f%%", standing.winRate * 100))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(.label))
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.8, blue: 0.0)
        case 2: return Color(.systemGray)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return Color(.label)
        }
    }

    private func gdString(_ gd: Int) -> String {
        gd > 0 ? "+\(gd)" : "\(gd)"
    }

    // MARK: - 일정

    // 날짜별 + blockName별 그룹 구조
    private struct DayGroup: Identifiable {
        let id: String
        let date: Date
        let blockGroups: [BlockGroup]
    }

    private struct BlockGroup: Identifiable {
        let id: String
        let blockName: String?
        let matches: [Match]
    }

    private func makeGroups(_ matches: [Match], ascending: Bool) -> [DayGroup] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: matches) { cal.startOfDay(for: $0.startTime) }
        let sortedDays = byDay.keys.sorted { ascending ? $0 < $1 : $0 > $1 }
        return sortedDays.map { day in
            let dayMatches = byDay[day]!.sorted { $0.startTime < $1.startTime }
            var rawGroups: [(String?, [Match])] = []
            for match in dayMatches {
                if rawGroups.last?.0 == match.blockName {
                    rawGroups[rawGroups.count - 1].1.append(match)
                } else {
                    rawGroups.append((match.blockName, [match]))
                }
            }
            let blockGroups = rawGroups.enumerated().map { i, g in
                BlockGroup(id: "\(day.timeIntervalSince1970)-\(i)", blockName: g.0, matches: g.1)
            }
            return DayGroup(id: "\(day.timeIntervalSince1970)", date: day, blockGroups: blockGroups)
        }
    }

    private var scheduleListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                if !viewModel.upcomingMatches.isEmpty {
                    Section {
                        ForEach(makeGroups(viewModel.upcomingMatches, ascending: true)) { dayGroup in
                            dayHeader(dayGroup.date)
                            ForEach(dayGroup.blockGroups) { blockGroup in
                                if let name = blockGroup.blockName {
                                    blockLabel(name)
                                }
                                ForEach(blockGroup.matches) { match in
                                    NavigationLink(value: match) {
                                        MatchCardView(match: match, isLive: false)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16).padding(.vertical, 4)
                                }
                            }
                        }
                    } header: {
                        sectionHeader("예정 경기")
                    }
                }

                if !viewModel.completedMatches.isEmpty {
                    Section {
                        ForEach(makeGroups(viewModel.completedMatches, ascending: false)) { dayGroup in
                            dayHeader(dayGroup.date)
                            ForEach(dayGroup.blockGroups) { blockGroup in
                                if let name = blockGroup.blockName {
                                    blockLabel(name)
                                }
                                ForEach(blockGroup.matches) { match in
                                    NavigationLink(value: match) {
                                        MatchCardView(match: match, isLive: false)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16).padding(.vertical, 4)
                                }
                            }
                        }
                    } header: {
                        sectionHeader("완료 경기")
                    }
                }

                if viewModel.upcomingMatches.isEmpty && viewModel.completedMatches.isEmpty {
                    emptyState("일정을 불러올 수 없습니다").padding(.top, 60)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        HStack {
            Text(date, style: .date)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
    }

    private func blockLabel(_ name: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3, height: 12)
            Text(name)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 3)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 팀

    private var teamsContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.standings.isEmpty {
                    emptyState("팀 데이터를 불러올 수 없습니다").padding(.top, 60)
                } else {
                    ForEach(viewModel.standings) { standing in
                        teamCard(standing: standing)
                    }
                }
            }
            .padding(16)
        }
    }

    private func teamCard(standing: Standing) -> some View {
        let roster = viewModel.players.filter { $0.teamId == standing.team.id }
        return VStack(spacing: 0) {
            NavigationLink(value: standing.team) {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: URL(string: standing.team.imageURL ?? ""))
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(standing.team.name)
                            .font(.subheadline).fontWeight(.semibold)
                        Text("\(standing.wins)승 \(standing.losses)패")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("#\(standing.rank)")
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(standing.rank <= 3 ? .primary : .secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if !roster.isEmpty {
                Divider().padding(.horizontal, 16)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(roster) { player in
                        playerChip(player)
                    }
                }
                .padding(12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playerChip(_ player: Player) -> some View {
        NavigationLink(value: player) {
            HStack(spacing: 8) {
                CachedAsyncImage(url: URL(string: player.imageURL ?? ""))
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(player.summonerName)
                        .font(.caption).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(roleLabel(player.role))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 선수

    private var playersContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.players.isEmpty {
                    emptyState("선수 데이터를 불러올 수 없습니다").padding(.top, 60)
                } else {
                    ForEach(viewModel.players) { player in
                        playerRow(player)
                        if player.id != viewModel.players.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(16)
        }
    }

    private func playerRow(_ player: Player) -> some View {
        NavigationLink(value: player) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: URL(string: player.imageURL ?? ""))
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.summonerName)
                        .font(.subheadline).fontWeight(.semibold)
                    if let first = player.firstName, let last = player.lastName,
                       !first.isEmpty || !last.isEmpty {
                        Text("\(first) \(last)".trimmingCharacters(in: .whitespaces))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    let teamImageURL = viewModel.standings
                        .first { $0.team.id == player.teamId }?.team.imageURL
                    CachedAsyncImage(url: URL(string: teamImageURL ?? ""))
                        .frame(width: 20, height: 20)

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
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func emptyState(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

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
