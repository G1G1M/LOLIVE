//
//  TodayView+MatchList.swift
//  LOLIVE
//
//  선택한 날짜의 경기 목록 — 리그별 그룹핑과 LIVE 필터 적용까지.
//

import SwiftUI

extension TodayView {

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

    var matchList: some View {
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
                await viewModel.loadTodayMatches(forceRefresh: true)
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
