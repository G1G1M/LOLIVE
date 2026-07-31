//
//  ContentView.swift
//  LOLIVE
//
//  Created by 김지원 on 5/15/26.
//

import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @Query private var favoriteTeams: [FavoriteTeam]
    @Environment(TodayViewModel.self) private var todayViewModel
    @AppStorage("primaryTeamCode") private var primaryTeamCode: String = ""
    @State private var selectedTab = 0
    @State private var searchFocusTrigger = 0

    private var themeColor: Color {
        primaryTeamCode.isEmpty ? Color.accentColor : TeamTheme.color(for: primaryTeamCode)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tag(0)
                .tabItem { Label("Today", systemImage: "house.fill") }

            LeaguesView()
                .tag(1)
                .tabItem { Label("Leagues", systemImage: "trophy.fill") }

            StandingsView()
                .tag(2)
                .tabItem { Label("Standings", systemImage: "list.number") }

            PlayersView()
                .tag(3)
                .tabItem { Label("Players", systemImage: "person.fill") }

            FavoritesView()
                .tag(4)
                .tabItem { Label("Favorites", systemImage: "star.fill") }

            SearchView(focusTrigger: searchFocusTrigger)
                .tag(5)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .tint(themeColor)
        .onChange(of: selectedTab) { _, new in
            if new == 5 {
                searchFocusTrigger += 1
            }
        }
        .task {
            syncFavoritedTeamIds()
            todayViewModel.startLivePolling()   // favoritedTeamIds 설정 직후 시작
            SharedDataService.saveFavoriteTeams(favoriteTeams)
            WidgetCenter.shared.reloadAllTimelines()
            await MatchNotificationService.shared.requestPermission()
            await MatchNotificationService.shared.reschedule(for: favoriteTeams)
        }
        .onChange(of: favoriteTeams) { _, newValue in
            syncFavoritedTeamIds()
            SharedDataService.saveFavoriteTeams(newValue)
            saveWidgetNextMatches()
            todayViewModel.syncLiveActivitiesNow()
            Task { await MatchNotificationService.shared.reschedule(for: newValue) }
        }
        .onChange(of: todayViewModel.upcomingMatches) { _, _ in
            saveWidgetNextMatches()
        }
        .onChange(of: todayViewModel.liveMatches) { _, _ in
            saveWidgetNextMatches()
        }
    }

    private func syncFavoritedTeamIds() {
        todayViewModel.favoritedTeamIds = Set(favoriteTeams.flatMap { [$0.teamId, $0.teamCode] })
    }

    private func sharedMatchEntry(match: Match, teamCode: String, liveMatch: LiveMatch?) -> SharedNextMatch {
        let isTeamA = match.teamA.code.lowercased() == teamCode.lowercased()
        let opponent = isTeamA ? match.teamB : match.teamA
        return SharedNextMatch(
            opponentName: opponent.name,
            opponentCode: opponent.code,
            opponentImageURL: opponent.imageURL,
            startTime: match.startTime,
            isLive: liveMatch != nil,
            leagueName: match.league.name,
            savedAt: Date(),
            myScore: isTeamA ? match.scoreA : match.scoreB,
            oppScore: isTeamA ? match.scoreB : match.scoreA,
            currentGame: liveMatch?.currentSet
        )
    }

    private func saveWidgetNextMatches() {
        let allMatches = todayViewModel.liveMatches.map { $0.match }
            + todayViewModel.todayMatches
            + todayViewModel.upcomingMatches

        var nextMatchMap: [String: SharedNextMatch] = [:]
        for fav in favoriteTeams {
            let code = fav.teamCode.lowercased()
            guard let match = allMatches.first(where: {
                $0.teamA.code.lowercased() == code || $0.teamB.code.lowercased() == code
            }) else { continue }
            let liveMatch = todayViewModel.liveMatches.first { $0.match.id == match.id }
            nextMatchMap[fav.teamCode.uppercased()] = sharedMatchEntry(match: match, teamCode: fav.teamCode, liveMatch: liveMatch)
        }

        // 즐겨찾기 여부와 무관하게 지금 라이브 중인 모든 팀도 스냅샷에 포함 —
        // 위젯 Extension이 이 스냅샷만으로 라이브 판정할 수 있게 해서 자체 API 재호출을 줄인다.
        for liveMatch in todayViewModel.liveMatches {
            for team in [liveMatch.match.teamA, liveMatch.match.teamB] {
                let key = team.code.uppercased()
                if nextMatchMap[key] == nil {
                    nextMatchMap[key] = sharedMatchEntry(match: liveMatch.match, teamCode: team.code, liveMatch: liveMatch)
                }
            }
        }

        SharedDataService.saveNextMatches(nextMatchMap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    ContentView()
        .environment(TodayViewModel())
}
