//
//  TodayView.swift
//  LOLIVE
//

import SwiftUI

struct TodayView: View {
    @Environment(TodayViewModel.self) private var viewModel
    @State private var showMenu = false
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showLiveOnly = false

    private let cal = Calendar.current

    // 과거 5일 ~ upcoming 마지막 경기 날짜 (없으면 +5일)
    private var dateRange: [Date] {
        let today = cal.startOfDay(for: Date())
        let lastUpcomingDay = viewModel.upcomingMatches.last.map { cal.startOfDay(for: $0.startTime) }
        let minEnd = cal.date(byAdding: .day, value: 5, to: today)!
        let end = max(lastUpcomingDay ?? minEnd, minEnd)
        let endDays = cal.dateComponents([.day], from: today, to: end).day ?? 5
        return (-5...endDays).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                titleHeader
                dateStrip
                favoritesToggle

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                    if viewModel.isLoading && viewModel.todayMatches.isEmpty {
                        LoadingView()
                    } else if viewModel.errorMessage != nil {
                        ErrorRetryView(viewModel.errorMessage ?? "데이터를 불러올 수 없습니다") {
                            Task { await viewModel.loadTodayMatches() }
                        }
                    } else {
                        matchList
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showMenu) { AppMenuView() }
            .navigationDestination(for: Match.self) { match in
                MatchDetailView(
                    match: match,
                    liveMatch: viewModel.liveMatches.first { $0.match.id == match.id }
                )
            }
        }
        .task {
            await viewModel.loadTodayMatches()
        }
    }

    // MARK: - Fixed: Title

    private var titleHeader: some View {
        HStack {
            Text("오늘의 경기")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(.label))
            Spacer()
            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Fixed: Date Strip

    private var dateStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(dateRange, id: \.self) { date in
                        dateChip(date).id(date)
                    }
                }
                .padding(.horizontal, 8)
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                proxy.scrollTo(cal.startOfDay(for: Date()), anchor: .center)
            }
            .onChange(of: selectedDate) { _, newDate in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newDate, anchor: .center)
                }
            }
        }
    }

    private func dateChip(_ date: Date) -> some View {
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isToday    = cal.isDateInToday(date)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedDate = date }
        } label: {
            VStack(spacing: 6) {
                // 요일
                Text(weekdayStr(date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                // 날짜 숫자 — 선택 시 숫자 뒤에만 원형 accent
                ZStack {
                    Circle()
                        .fill(
                            isSelected ? Color.accentColor
                            : isToday  ? Color.accentColor.opacity(0.12)
                            : Color.clear
                        )
                        .frame(width: 36, height: 36)

                    Text(dayStr(date))
                        .font(.system(size: 17, weight: (isSelected || isToday) ? .bold : .regular))
                        .foregroundStyle(
                            isSelected ? Color.white
                            : isToday  ? Color.accentColor
                            : Color(.label)
                        )
                }
            }
            .frame(width: 52)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private func weekdayStr(_ date: Date) -> String {
        Self.weekdayFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private func dayStr(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    // MARK: - Fixed: Favorites Toggle

    private var favoritesToggle: some View {
        HStack(spacing: 8) {
            filterPill(title: "전체", isSelected: !viewModel.showFavoritesOnly && !showLiveOnly) {
                viewModel.showFavoritesOnly = false
                showLiveOnly = false
            }
            if viewModel.hasFavoriteTeams {
                filterPill(title: "★ 즐겨찾기", isSelected: viewModel.showFavoritesOnly && !showLiveOnly) {
                    viewModel.showFavoritesOnly = true
                    showLiveOnly = false
                }
            }
            liveFilterPill
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.15), value: viewModel.showFavoritesOnly)
        .animation(.easeInOut(duration: 0.15), value: showLiveOnly)
    }

    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var liveFilterPill: some View {
        Button {
            showLiveOnly = true
            viewModel.showFavoritesOnly = false
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(showLiveOnly ? Color.white : Color.red)
                    .frame(width: 6, height: 6)
                Text("LIVE")
            }
            .font(.subheadline).fontWeight(.semibold)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(showLiveOnly ? Color.red : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(showLiveOnly ? Color.white : Color.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Structures

    private struct LeagueMatchGroup: Identifiable {
        var id: String { league.id }
        let league: League
        let matches: [(match: Match, isLive: Bool)]
    }

    private var groupsForSelectedDate: [LeagueMatchGroup] {
        let isToday = cal.isDateInToday(selectedDate)
        var byLeague: [String: (League, [(Match, Bool)])] = [:]
        var addedMatchIds = Set<String>()

        func add(_ match: Match, isLive: Bool) {
            guard addedMatchIds.insert(match.id).inserted else { return }
            let lid = match.league.id
            if byLeague[lid] == nil { byLeague[lid] = (match.league, []) }
            byLeague[lid]!.1.append((match, isLive))
        }

        if isToday {
            for lm in viewModel.filteredLiveMatches { add(lm.match, isLive: true) }
        }
        for m in viewModel.filteredTodayMatches + viewModel.filteredUpcomingMatches {
            if cal.isDate(m.startTime, inSameDayAs: selectedDate) { add(m, isLive: false) }
        }
        for m in viewModel.filteredCompletedMatches {
            if cal.isDate(m.startTime, inSameDayAs: selectedDate) { add(m, isLive: false) }
        }

        return byLeague.values.map { (league, pairs) in
            let sorted = pairs.sorted { a, b in
                if a.1 != b.1 { return a.1 }
                return a.0.startTime < b.0.startTime
            }
            return LeagueMatchGroup(league: league, matches: sorted)
        }.sorted { a, b in
            let aLive = a.matches.contains { $0.isLive }
            let bLive = b.matches.contains { $0.isLive }
            if aLive != bLive { return aLive }
            return a.league.name < b.league.name
        }
    }

    /// getLive 목록 여부(isLive)와 스케줄 상태(inProgress) 중 하나만 맞아도 라이브로 간주 —
    /// MatchCardView의 isEffectivelyLive 판정과 동일한 기준을 필터에도 적용한다.
    private var displayedGroups: [LeagueMatchGroup] {
        guard showLiveOnly else { return groupsForSelectedDate }
        return groupsForSelectedDate.compactMap { group in
            let live = group.matches.filter { $0.isLive || $0.match.state == .inProgress }
            guard !live.isEmpty else { return nil }
            return LeagueMatchGroup(league: group.league, matches: live)
        }
    }

    // MARK: - Match List

    private var matchList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    Color.clear.frame(height: 0).id("top")

                    if showLiveOnly && displayedGroups.isEmpty {
                        EmptyStateView("현재 라이브 중인 경기가 없습니다", icon: "dot.radiowaves.left.and.right")
                    } else if viewModel.showFavoritesOnly && displayedGroups.isEmpty {
                        EmptyStateView("즐겨찾기한 팀의 경기가 없습니다", icon: "star.slash")
                    } else if displayedGroups.isEmpty {
                        EmptyStateView("이 날짜에 경기가 없습니다", icon: "calendar.badge.exclamationmark")
                    } else {
                        ForEach(displayedGroups) { group in
                            Section {
                                ForEach(group.matches, id: \.match.id) { (match, isLive) in
                                    NavigationLink(value: match) {
                                        MatchCardView(match: match, isLive: isLive)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 5)
                                }
                                .padding(.bottom, 8)
                            } header: {
                                LeagueSectionHeader(league: group.league)
                            }
                        }

                    }
                }
                .padding(.bottom, 20)
            }
            .refreshable {
                await viewModel.loadTodayMatches()
                proxy.scrollTo("top", anchor: .top)
            }
            .onChange(of: selectedDate) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
        }
    }

}

#Preview {
    TodayView()
        .environment(TodayViewModel())
        .preferredColorScheme(.dark)
}
