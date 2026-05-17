//
//  TodayView.swift
//  LOLIVE
//

import SwiftUI

struct TodayView: View {
    @Environment(TodayViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if viewModel.isLoading && viewModel.todayMatches.isEmpty {
                    ProgressView("불러오는 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    matchList
                }
            }
            .navigationTitle("오늘의 경기")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .navigationDestination(for: Match.self) { match in
                MatchDetailView(
                    match: match,
                    liveMatch: viewModel.liveMatches.first { $0.match.id == match.id }
                )
            }
            .alert("오류", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("확인") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task {
            await viewModel.loadTodayMatches()
            viewModel.startLivePolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Date Grouping Helpers

    private struct LeagueGroup: Identifiable {
        var id: String { leagueId }
        let leagueId: String
        let league: League?
        let matches: [Match]
    }

    private struct DateGroup: Identifiable {
        let id: String
        let date: Date
        let leagueGroups: [LeagueGroup]
    }

    private func groupByDate(_ matches: [Match], ascending: Bool) -> [DateGroup] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: matches) { cal.startOfDay(for: $0.startTime) }
        let sortedDays = byDay.keys.sorted { ascending ? $0 < $1 : $0 > $1 }
        return sortedDays.map { day in
            let dayMatches = byDay[day]!.sorted { $0.startTime < $1.startTime }
            let byLeague = Dictionary(grouping: dayMatches) { $0.league.id }
            let leagueGroups = byLeague.keys.sorted().map { lid in
                LeagueGroup(leagueId: lid,
                            league: byLeague[lid]?.first?.league,
                            matches: byLeague[lid]!)
            }
            return DateGroup(id: "\(day.timeIntervalSince1970)", date: day, leagueGroups: leagueGroups)
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        if cal.isDateInTomorrow(date)  { return "내일" }
        return date.formatted(.dateTime.month().day().weekday().locale(Locale(identifier: "ko_KR")))
    }

    private func dateSubHeader(_ date: Date) -> some View {
        HStack {
            Text(dateLabel(date))
                .font(.subheadline).fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
    }

    // MARK: - Match List

    private var matchList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    Color.clear.frame(height: 0).id("top")
                    if viewModel.hasFavoriteTeams {
                        favoritesToggle
                    }
                    if viewModel.isFavoritesFilterEmpty {
                        favoritesEmptyView
                    } else {
                        if !viewModel.filteredLiveMatches.isEmpty {
                            liveSection
                        }
                        if !viewModel.filteredTodayMatches.isEmpty {
                            scheduledSection
                        }
                        if !viewModel.filteredUpcomingMatches.isEmpty {
                            upcomingSection
                        }
                        if !viewModel.filteredCompletedMatches.isEmpty {
                            completedSection
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .refreshable {
                await viewModel.loadTodayMatches()
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private var favoritesToggle: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.showFavoritesOnly = false
            } label: {
                Text("전체")
                    .font(.subheadline).fontWeight(.semibold)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(viewModel.showFavoritesOnly ? Color.clear : Color.accentColor)
                    .foregroundStyle(viewModel.showFavoritesOnly ? Color.secondary : Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(viewModel.showFavoritesOnly ? Color.secondary.opacity(0.3) : Color.clear))
            }
            Button {
                viewModel.showFavoritesOnly = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                    Text("즐겨찾기")
                        .font(.subheadline).fontWeight(.semibold)
                }
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(viewModel.showFavoritesOnly ? Color.accentColor : Color.clear)
                .foregroundStyle(viewModel.showFavoritesOnly ? Color.white : Color.secondary)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(viewModel.showFavoritesOnly ? Color.clear : Color.secondary.opacity(0.3)))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: viewModel.showFavoritesOnly)
    }

    private var favoritesEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("즐겨찾기한 팀의 경기가 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Sections

    private var liveSection: some View {
        Section {
            let grouped = Dictionary(grouping: viewModel.filteredLiveMatches) { $0.match.league.id }
            ForEach(grouped.keys.sorted(), id: \.self) { leagueId in
                if let items = grouped[leagueId], let league = items.first?.match.league {
                    LeagueSectionHeader(league: league)
                    ForEach(items) { liveMatch in
                        NavigationLink(value: liveMatch.match) {
                            MatchCardView(match: liveMatch.match, isLive: true)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            sectionTitle("LIVE", color: .red)
        }
    }

    private var scheduledSection: some View {
        Section {
            let grouped = Dictionary(grouping: viewModel.filteredTodayMatches) { $0.league.id }
            ForEach(grouped.keys.sorted(), id: \.self) { leagueId in
                if let matches = grouped[leagueId], let league = matches.first?.league {
                    LeagueSectionHeader(league: league)
                    ForEach(matches) { match in
                        NavigationLink(value: match) {
                            MatchCardView(match: match, isLive: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            sectionTitle("오늘 예정", color: .primary)
        }
    }

    private var upcomingSection: some View {
        Section {
            ForEach(groupByDate(viewModel.filteredUpcomingMatches, ascending: true)) { dayGroup in
                dateSubHeader(dayGroup.date)
                ForEach(dayGroup.leagueGroups) { group in
                    if let league = group.league {
                        LeagueSectionHeader(league: league)
                    }
                    ForEach(group.matches) { match in
                        NavigationLink(value: match) {
                            MatchCardView(match: match, isLive: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            sectionTitle("예정 경기", color: .primary)
        }
    }

    private var completedSection: some View {
        Section {
            let allCompleted = viewModel.filteredCompletedMatches
            let limit = viewModel.completedMatchesLimit
            let visible = viewModel.showAllCompleted
                ? allCompleted
                : Array(allCompleted.prefix(limit))

            ForEach(groupByDate(visible, ascending: false)) { dayGroup in
                dateSubHeader(dayGroup.date)
                ForEach(dayGroup.leagueGroups) { group in
                    if let league = group.league {
                        LeagueSectionHeader(league: league)
                    }
                    ForEach(group.matches) { match in
                        NavigationLink(value: match) {
                            MatchCardView(match: match, isLive: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }

            if allCompleted.count > limit {
                Button {
                    viewModel.showAllCompleted.toggle()
                } label: {
                    HStack {
                        Text(viewModel.showAllCompleted
                             ? "접기"
                             : "더 보기 (\(allCompleted.count - limit)개)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: viewModel.showAllCompleted
                              ? "chevron.up"
                              : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        } header: {
            sectionTitle("완료된 경기", color: .secondary)
        }
    }

    // MARK: - Section Title

    private func sectionTitle(_ title: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    TodayView()
        .environment(TodayViewModel())
        .preferredColorScheme(.dark)
}
