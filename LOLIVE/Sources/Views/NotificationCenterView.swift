//
//  NotificationCenterView.swift
//  LOLIVE
//

import SwiftUI
import UserNotifications

struct NotificationCenterView: View {

    @State private var items: [PendingItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "예정 알림 없음",
                    systemImage: "bell.slash",
                    description: Text("즐겨찾기 팀의 예정된 경기 알림이 없습니다")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    if let info = item.matchInfo {
                        NavigationLink(destination: MatchDetailView(match: info.match)) {
                            itemRow(item)
                        }
                    } else {
                        itemRow(item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("예정 알림")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPending() }
    }

    private func itemRow(_ item: PendingItem) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: item.myTeamImageURL.flatMap { URL(string: $0) })
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(item.myTeamName)
                        .font(.subheadline).fontWeight(.semibold)
                    Text("vs")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.opponentName)
                        .font(.subheadline)
                }
                Text(item.leagueName)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.fireDate, style: .date)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(item.fireDate, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadPending() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()

        let matchRequests = requests
            .filter { $0.identifier.hasPrefix("lolive_match_") }
            .sorted { r1, r2 in
                guard let d1 = triggerDate(r1.trigger), let d2 = triggerDate(r2.trigger) else { return false }
                return d1 < d2
            }

        items = matchRequests.compactMap { request in
            guard let fireDate = triggerDate(request.trigger) else { return nil }
            let userInfo = request.content.userInfo
            let info = MatchDeepLinkInfo(userInfo: userInfo)

            let favCode = userInfo["favTeamCode"] as? String ?? ""
            let teamACode = userInfo["teamACode"] as? String ?? ""
            let isTeamA = teamACode.lowercased() == favCode.lowercased()

            let myTeamName = isTeamA
                ? (userInfo["teamAName"] as? String ?? "")
                : (userInfo["teamBName"] as? String ?? "")
            let myTeamImage = isTeamA
                ? (userInfo["teamAImage"] as? String)
                : (userInfo["teamBImage"] as? String)
            let oppName = isTeamA
                ? (userInfo["teamBName"] as? String ?? "")
                : (userInfo["teamAName"] as? String ?? "")
            let leagueName = userInfo["leagueName"] as? String ?? ""

            return PendingItem(
                id: request.identifier,
                myTeamName: myTeamName,
                myTeamImageURL: myTeamImage,
                opponentName: oppName,
                leagueName: leagueName,
                fireDate: fireDate,
                matchInfo: info
            )
        }

        isLoading = false
    }

    private func triggerDate(_ trigger: UNNotificationTrigger?) -> Date? {
        if let t = trigger as? UNCalendarNotificationTrigger {
            return t.nextTriggerDate()
        }
        if let t = trigger as? UNTimeIntervalNotificationTrigger {
            return Date().addingTimeInterval(t.timeInterval)
        }
        return nil
    }

    // MARK: - Model

    struct PendingItem: Identifiable {
        let id: String
        let myTeamName: String
        let myTeamImageURL: String?
        let opponentName: String
        let leagueName: String
        let fireDate: Date
        let matchInfo: MatchDeepLinkInfo?
    }
}
