//
//  LOLIVEApp.swift
//  LOLIVE
//
//  Created by 김지원 on 5/15/26.
//

import SwiftUI
import SwiftData
import UserNotifications
import ActivityKit

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
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var phase: AppPhase = .splash
    @State private var todayViewModel = TodayViewModel()
    @State private var deepLinkTeam: TeamDeepLinkItem?
    @State private var deepLinkMatch: MatchDeepLinkInfo?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = LOLIVENotificationDelegate.shared
        _ = SystemAppearance.isDark // 오버라이드가 걸리기 전, 앱 시작 시점에 미리 캐싱
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
                        .onAppear { AppPreloadService.shared.start() }
                        .onOpenURL { url in
                            guard url.scheme == "lolive", !url.pathComponents.isEmpty else { return }
                            if url.host == "match",
                               let teamCode = url.pathComponents.dropFirst().first,
                               !teamCode.isEmpty {
                                // 위젯 탭: 해당 팀의 다음 경기로 이동
                                deepLinkTeam = TeamDeepLinkItem(id: teamCode.uppercased())
                            } else if url.host == "team",
                                      let teamCode = url.pathComponents.dropFirst().first,
                                      !teamCode.isEmpty {
                                deepLinkTeam = TeamDeepLinkItem(id: teamCode.uppercased())
                            }
                        }
                        .sheet(item: $deepLinkTeam) { item in
                            WidgetMatchDeepLinkSheet(teamCode: item.id)
                                .environment(todayViewModel)
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
            .preferredColorScheme(appTheme.resolvedColorScheme)
            // 화면 모드 전환 시 전체 화면 크로스페이드가 세그먼트 버튼 애니메이션과 겹쳐
            // 버벅이는 느낌이 났음 — 모드 전환 자체는 애니메이션 없이 즉시 바뀌게 함
            .animation(nil, value: appTheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 포그라운드 복귀 시 즉시 폴링 재시작 → 백그라운드 중 시작된 경기도 즉각 감지
            guard phase == .main, newPhase == .active else { return }
            todayViewModel.startLivePolling()
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
    let id: String  // teamCode (대문자)
}

/// 위젯 탭 → 해당 팀의 다음/진행 중 경기 상세로 이동
struct WidgetMatchDeepLinkSheet: View {
    let teamCode: String
    @Environment(TodayViewModel.self) private var todayViewModel

    private var match: Match? {
        let code = teamCode.uppercased()
        let allMatches = todayViewModel.liveMatches.map { $0.match }
            + todayViewModel.todayMatches
            + todayViewModel.upcomingMatches
        return allMatches.first {
            $0.teamA.code.uppercased() == code || $0.teamB.code.uppercased() == code
        }
    }

    var body: some View {
        if todayViewModel.isLoading && match == nil {
            ProgressView("경기 정보 불러오는 중...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let match {
            NavigationStack {
                MatchDetailView(
                    match: match,
                    liveMatch: todayViewModel.liveMatches.first { $0.match.id == match.id }
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            ContentUnavailableView(
                "경기 없음",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("현재 예정된 경기가 없습니다.")
            )
        }
    }
}
