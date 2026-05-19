//
//  LOLIVEApp.swift
//  LOLIVE
//
//  Created by 김지원 on 5/15/26.
//

import SwiftUI
import SwiftData

// MARK: - App Phase

private enum AppPhase {
    case splash
    case onboarding
    case main
}

// MARK: - App

@main
struct LOLIVEApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var phase: AppPhase = .splash
    @State private var todayViewModel = TodayViewModel()
    @State private var deepLinkTeam: TeamDeepLinkItem?

    var body: some Scene {
        WindowGroup {
            Group {
                switch phase {
                case .splash:
                    SplashView()
                        .onAppear { scheduleSplashEnd() }

                case .onboarding:
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            hasCompletedOnboarding = true
                            phase = .main
                        }
                    }

                case .main:
                    ContentView()
                        .environment(todayViewModel)
                        .onOpenURL { url in
                            guard url.scheme == "lolive",
                                  url.host == "team",
                                  let teamId = url.pathComponents.dropFirst().first,
                                  !teamId.isEmpty
                            else { return }
                            deepLinkTeam = TeamDeepLinkItem(id: teamId)
                        }
                        .sheet(item: $deepLinkTeam) { item in
                            TeamDeepLinkSheet(teamId: item.id)
                        }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: phase)
        }
        .modelContainer(for: [FavoriteTeam.self, FavoritePlayer.self])
    }

    private func scheduleSplashEnd() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                phase = hasCompletedOnboarding ? .main : .onboarding
            }
        }
    }
}

// MARK: - Deep Link Types

struct TeamDeepLinkItem: Identifiable {
    let id: String  // Riot team ID
}

struct TeamDeepLinkSheet: View {
    let teamId: String
    @Query private var favoriteTeams: [FavoriteTeam]

    var body: some View {
        if let fav = favoriteTeams.first(where: { $0.teamId == teamId }) {
            NavigationStack {
                TeamDetailView(team: fav.asTeam, league: fav.asLeague)
            }
        } else {
            ContentUnavailableView(
                "팀 정보 없음",
                systemImage: "star.slash",
                description: Text("즐겨찾기에 등록된 팀을 찾을 수 없습니다.")
            )
        }
    }
}
