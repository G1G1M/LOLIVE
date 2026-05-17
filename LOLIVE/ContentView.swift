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

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }

            LeaguesView()
                .tabItem { Label("Leagues", systemImage: "trophy.fill") }

            StandingsView()
                .tabItem { Label("Standings", systemImage: "chart.bar.fill") }

            PlayersView()
                .tabItem { Label("Players", systemImage: "person.fill") }

            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "star.fill") }
        }
        .preferredColorScheme(.dark)
        .task {
            // await 이전에 동기로 저장 — task가 취소(백그라운드 전환 등)되어도 반드시 실행됨
            syncFavoritedTeamIds()
            SharedDataService.saveFavoriteTeams(favoriteTeams)
            WidgetCenter.shared.reloadAllTimelines()
            // 이후 async 작업 (취소 가능)
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
