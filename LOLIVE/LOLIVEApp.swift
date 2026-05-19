//
//  LOLIVEApp.swift
//  LOLIVE
//
//  Created by 김지원 on 5/15/26.
//

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - App Phase

private enum AppPhase {
    case splash
    case onboarding
    case main
}

// MARK: - Notification Delegate

final class LOLIVENotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = LOLIVENotificationDelegate()
    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let info = MatchDeepLinkInfo(userInfo: userInfo) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .loliveMatchDeepLink,
                    object: nil,
                    userInfo: ["info": info]
                )
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - App

@main
struct LOLIVEApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var phase: AppPhase = .splash
    @State private var todayViewModel = TodayViewModel()
    @State private var deepLinkTeam: TeamDeepLinkItem?
    @State private var deepLinkMatch: MatchDeepLinkInfo?

    init() {
        UNUserNotificationCenter.current().delegate = LOLIVENotificationDelegate.shared
    }

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
                        .sheet(item: $deepLinkMatch) { info in
                            NavigationStack {
                                MatchDetailView(match: info.match)
                            }
                        }
                        .onReceive(
                            NotificationCenter.default.publisher(for: .loliveMatchDeepLink)
                        ) { notification in
                            if let info = notification.userInfo?["info"] as? MatchDeepLinkInfo {
                                deepLinkMatch = info
                            }
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

extension Notification.Name {
    static let loliveMatchDeepLink = Notification.Name("loliveMatchDeepLink")
}

struct MatchDeepLinkInfo: Identifiable {
    let id: String  // matchId
    let match: Match

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let matchId = userInfo["matchId"] as? String,
            let leagueId = userInfo["leagueId"] as? String,
            let leagueName = userInfo["leagueName"] as? String,
            let leagueRegion = userInfo["leagueRegion"] as? String,
            let teamACode = userInfo["teamACode"] as? String,
            let teamAName = userInfo["teamAName"] as? String,
            let teamBCode = userInfo["teamBCode"] as? String,
            let teamBName = userInfo["teamBName"] as? String,
            let startTimeISO = userInfo["startTimeISO"] as? String
        else { return nil }

        let startTime = ISO8601DateFormatter().date(from: startTimeISO) ?? Date()
        let league = League(id: leagueId, slug: "", name: leagueName,
                            region: leagueRegion, imageURL: nil)
        let teamA = Team(
            id: userInfo["teamAId"] as? String ?? "",
            name: teamAName, code: teamACode,
            imageURL: (userInfo["teamAImage"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
        let teamB = Team(
            id: userInfo["teamBId"] as? String ?? "",
            name: teamBName, code: teamBCode,
            imageURL: (userInfo["teamBImage"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
        self.id = matchId
        self.match = Match(id: matchId, league: league, teamA: teamA, teamB: teamB,
                           scoreA: 0, scoreB: 0, startTime: startTime, state: .unstarted)
    }
}

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
