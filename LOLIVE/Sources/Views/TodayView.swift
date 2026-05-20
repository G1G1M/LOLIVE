//
//  TodayView.swift
//  LOLIVE
//

import SwiftUI

struct TodayView: View {
    @Environment(TodayViewModel.self) private var viewModel
    @State private var showMenu = false
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private let cal = Calendar.current

    // 오늘 기준 ±5일 (총 11일)
    private var dateRange: [Date] {
        let today = cal.startOfDay(for: Date())
        return (-5...5).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                titleHeader
                dateStrip
                if viewModel.hasFavoriteTeams { favoritesToggle }

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                    if viewModel.isLoading && viewModel.todayMatches.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: selectedDate) {
            viewModel.showAllCompleted = false
        }
        .onDisappear { viewModel.stopPolling() }
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

    private func weekdayStr(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "EEE"
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private func dayStr(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    // MARK: - Fixed: Favorites Toggle

    private var favoritesToggle: some View {
        HStack(spacing: 8) {
            filterPill(title: "전체", isSelected: !viewModel.showFavoritesOnly) {
                viewModel.showFavoritesOnly = false
            }
            filterPill(title: "★ 즐겨찾기", isSelected: viewModel.showFavoritesOnly) {
                viewModel.showFavoritesOnly = true
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.15), value: viewModel.showFavoritesOnly)
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

    // MARK: - Data Structures

    private struct LeagueMatchGroup: Identifiable {
        var id: String { league.id }
        let league: League
        let matches: [(match: Match, isLive: Bool)]
    }

    private var groupsForSelectedDate: [LeagueMatchGroup] {
        let isToday = cal.isDateInToday(selectedDate)
        var byLeague: [String: (League, [(Match, Bool)])] = [:]

        func add(_ match: Match, isLive: Bool) {
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
        for m in viewModel.displayedCompletedMatches {
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

    // MARK: - Match List

    private var matchList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    Color.clear.frame(height: 0).id("top")

                    if viewModel.showFavoritesOnly && groupsForSelectedDate.isEmpty {
                        emptyView(
                            icon: "star.slash",
                            message: "즐겨찾기한 팀의 경기가 없습니다"
                        )
                    } else if groupsForSelectedDate.isEmpty {
                        emptyView(
                            icon: "calendar.badge.exclamationmark",
                            message: "이 날짜에 경기가 없습니다"
                        )
                    } else {
                        ForEach(groupsForSelectedDate) { group in
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

                        if viewModel.hasMoreCompleted {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.showAllCompleted = true
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("완료된 경기 더 보기")
                                        .font(.subheadline).fontWeight(.medium)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .refreshable {
                await viewModel.loadTodayMatches()
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private func emptyView(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

#Preview {
    TodayView()
        .environment(TodayViewModel())
        .preferredColorScheme(.dark)
}
