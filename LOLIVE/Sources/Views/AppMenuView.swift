//
//  AppMenuView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct AppMenuView: View {
    @Query(sort: \FavoriteTeam.addedAt, order: .reverse) private var favoriteTeams: [FavoriteTeam]
    @AppStorage("notificationMinutesBefore") private var notificationMinutes: Int = 60
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @Environment(\.dismiss) private var dismiss
    // 시트 바깥(ContentView)에서 물려받는 실제 색상 모드 — appTheme이 "시스템 기본"일 때
    // 이 값을 그대로 쓴다. iOS 26.3(2026-08 기준)에서 라이트/다크처럼 값이 있던 상태에서
    // "시스템 기본"(nil)으로 바뀌면 이미 떠 있는 시트에는 반영이 안 되는 버그가 있어서
    // (nil로의 전환만 씹힘, 값이 있는 전환끼리는 정상) nil을 아예 넘기지 않고 항상
    // 구체적인 라이트/다크 값으로 대체해서 이 버그를 우회한다.
    @Environment(\.colorScheme) private var ambientColorScheme

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 알림 설정
                Section {
                    Picker("알림 시간", selection: $notificationMinutes) {
                        Text("1시간 전").tag(60)
                        Text("30분 전").tag(30)
                        Text("15분 전").tag(15)
                        Text("5분 전").tag(5)
                    }

                    NavigationLink(destination: NotificationCenterView()) {
                        Label("예정 알림 보기", systemImage: "bell.badge")
                    }
                } header: {
                    Text("알림 설정")
                }

                // MARK: - 앱 설정
                Section {
                    NavigationLink(destination: AppSettingsView()) {
                        Label("앱 설정", systemImage: "gearshape")
                    }
                } header: {
                    Text("설정")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("메뉴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .onChange(of: notificationMinutes) { _, _ in
                Task { await MatchNotificationService.shared.reschedule(for: favoriteTeams) }
            }
        }
        // 시트로 띄워진 화면이라 루트(LOLIVEApp)의 preferredColorScheme가 이미 열려있는
        // 이 시트에는 바로 반영이 안 될 수 있음 — 여기서도 직접 적용해 설정 화면 안에서
        // 테마를 바꾸면 그 자리에서 즉시 반영되게 한다.
        .preferredColorScheme(resolvedColorScheme)
        // 화면 모드 전환 시 전체 화면이 크로스페이드되면서 세그먼트 버튼 애니메이션과 겹쳐
        // 버벅이는 느낌이 났음 — 모드 전환 자체는 애니메이션 없이 즉시 바뀌게 함
        .animation(nil, value: appTheme)
    }

    private var resolvedColorScheme: ColorScheme {
        switch appTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return ambientColorScheme
        }
    }
}

#Preview {
    AppMenuView()
        .preferredColorScheme(.dark)
}
