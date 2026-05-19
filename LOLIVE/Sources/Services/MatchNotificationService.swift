//
//  MatchNotificationService.swift
//  LOLIVE
//

import Foundation
import UserNotifications

final class MatchNotificationService: Sendable {

    static let shared = MatchNotificationService()
    private let service = RiotEsportsService()

    private init() {}

    // MARK: - Public

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// 즐겨찾기 팀 목록이 바뀔 때마다 호출 — 기존 알림 제거 후 재스케줄
    func reschedule(for favoriteTeams: [FavoriteTeam]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .filter { $0.identifier.hasPrefix("lolive_match_") }
            .map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        await withTaskGroup(of: Void.self) { group in
            for fav in favoriteTeams {
                group.addTask { await self.schedule(for: fav) }
            }
        }
    }

    // MARK: - Private

    private func schedule(for fav: FavoriteTeam) async {
        guard let matches = try? await service.fetchSchedule(league: fav.asLeague) else { return }

        let now = Date()
        let center = UNUserNotificationCenter.current()

        let upcoming = matches.filter {
            $0.state == .unstarted &&
            $0.startTime > now &&
            ($0.teamA.code.lowercased() == fav.teamCode.lowercased() ||
             $0.teamB.code.lowercased() == fav.teamCode.lowercased())
        }

        for match in upcoming {
            let opponent = match.teamA.code.lowercased() == fav.teamCode.lowercased()
                ? match.teamB : match.teamA

            let fireDate = match.startTime.addingTimeInterval(-3600)
            if fireDate > now {
                // 정상: 경기 1시간 전 예약 알림
                let content = UNMutableNotificationContent()
                content.title = "\(fav.teamName) 경기 1시간 전"
                content.body = "vs \(opponent.name) · \(fav.leagueName)"
                content.sound = .default

                var dc = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )
                dc.second = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "lolive_match_\(match.id)_\(fav.teamId)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            } else if match.startTime > now {
                // 즐겨찾기 추가 시점에 이미 1시간 이내 → 즉시 알림
                let content = UNMutableNotificationContent()
                content.title = "\(fav.teamName) 경기가 곧 시작됩니다!"
                content.body = "vs \(opponent.name) · \(fav.leagueName)"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "lolive_match_\(match.id)_\(fav.teamId)_soon",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }
}
