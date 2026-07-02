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

            PlayersView()
                .tag(2)
                .tabItem { Label("Players", systemImage: "person.fill") }

            FavoritesView()
                .tag(3)
                .tabItem { Label("Favorites", systemImage: "star.fill") }

            SearchView(focusTrigger: searchFocusTrigger)
                .tag(4)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .tint(themeColor)
        .onChange(of: selectedTab) { _, new in
            if new == 4 {
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
            WidgetCenter.shared.reloadAllTimelines()
            todayViewModel.syncLiveActivitiesNow()
            Task { await MatchNotificationService.shared.reschedule(for: newValue) }
        }
    }

    private func syncFavoritedTeamIds() {
        todayViewModel.favoritedTeamIds = Set(favoriteTeams.flatMap { [$0.teamId, $0.teamCode] })
    }
}

#Preview {
    ContentView()
        .environment(TodayViewModel())
}
