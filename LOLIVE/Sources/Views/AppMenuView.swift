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
        .preferredColorScheme(appTheme.colorScheme)
    }
}

#Preview {
    AppMenuView()
        .preferredColorScheme(.dark)
}
