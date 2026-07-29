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

    // MARK: - Public (경기/세트 진행 알림)

    func sendResultNotification(for match: Match, favoriteTeamCode: String) async {
        let p = perspective(for: match, favoriteTeamCode: favoriteTeamCode)

        let content = UNMutableNotificationContent()
        content.title = p.myScore > p.oppScore ? "\(p.myTeam.name) 승리" : "\(p.myTeam.name) 패배"
        content.body  = "\(p.myScore) - \(p.oppScore)  vs \(p.opponent.name)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lolive_result_\(match.id)_\(favoriteTeamCode.lowercased())",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 즐겨찾기 팀 경기가 라이브로 전환된 시점(최초 감지)에 발송
    func sendMatchStartNotification(for match: Match, favoriteTeamCode: String) async {
        let p = perspective(for: match, favoriteTeamCode: favoriteTeamCode)

        let content = UNMutableNotificationContent()
        content.title = "\(p.myTeam.name) 경기 시작"
        content.body  = "vs \(p.opponent.name) · \(match.league.name)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lolive_start_\(match.id)_\(favoriteTeamCode.lowercased())",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 세트 번호(currentSet)가 증가한 시점 — 방금 끝난 세트 결과 알림
    func sendSetEndNotification(for match: Match, favoriteTeamCode: String, endedSet: Int) async {
        let p = perspective(for: match, favoriteTeamCode: favoriteTeamCode)

        let content = UNMutableNotificationContent()
        content.title = "Game \(endedSet) 종료"
        content.body  = "\(p.myTeam.code) \(p.myScore) - \(p.oppScore) \(p.opponent.code)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lolive_setend_\(match.id)_\(endedSet)_\(favoriteTeamCode.lowercased())",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// 세트 번호(currentSet)가 증가한 시점 — 다음 세트 시작 알림
    func sendSetStartNotification(for match: Match, favoriteTeamCode: String, newSet: Int) async {
        let p = perspective(for: match, favoriteTeamCode: favoriteTeamCode)

        let content = UNMutableNotificationContent()
        content.title = "Game \(newSet) 시작"
        content.body  = "\(p.myTeam.code) vs \(p.opponent.code) · \(match.league.name)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lolive_setstart_\(match.id)_\(newSet)_\(favoriteTeamCode.lowercased())",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 테스트 (DEBUG 빌드 전용)

    #if DEBUG
    /// 실제 경기 시간과 무관하게 5초 후 발송되는 테스트 알림.
    /// 앱 설정 > 테스트 섹션에서 호출된다.
    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "T1 경기 1시간 전"
        content.body = "vs Gen.G · LCK (테스트 알림)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lolive_test_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
    #endif

    // MARK: - Private

    private struct MatchPerspective {
        let myTeam: Team
        let opponent: Team
        let myScore: Int
        let oppScore: Int
    }

    /// 즐겨찾기 팀 기준으로 우리팀/상대팀/스코어를 정리
    private func perspective(for match: Match, favoriteTeamCode: String) -> MatchPerspective {
        let isTeamA = match.teamA.code.lowercased() == favoriteTeamCode.lowercased()
        return MatchPerspective(
            myTeam: isTeamA ? match.teamA : match.teamB,
            opponent: isTeamA ? match.teamB : match.teamA,
            myScore: isTeamA ? match.scoreA : match.scoreB,
            oppScore: isTeamA ? match.scoreB : match.scoreA
        )
    }

    private var minutesBefore: Int {
        let stored = UserDefaults.standard.integer(forKey: "notificationMinutesBefore")
        return stored > 0 ? stored : 60
    }

    private func notificationTitle(teamName: String, minutes: Int) -> String {
        minutes >= 60 ? "\(teamName) 경기 \(minutes / 60)시간 전" : "\(teamName) 경기 \(minutes)분 전"
    }

    private func schedule(for fav: FavoriteTeam) async {
        guard let matches = try? await service.fetchSchedule(league: fav.asLeague) else { return }

        let now = Date()
        let center = UNUserNotificationCenter.current()
        let minutes = minutesBefore
        let isoFormatter = ISO8601DateFormatter()

        let upcoming = matches.filter {
            $0.state == .unstarted &&
            $0.startTime > now &&
            ($0.teamA.code.lowercased() == fav.teamCode.lowercased() ||
             $0.teamB.code.lowercased() == fav.teamCode.lowercased())
        }

        for match in upcoming {
            let isTeamA = match.teamA.code.lowercased() == fav.teamCode.lowercased()
            let opponent = isTeamA ? match.teamB : match.teamA

            // Deep link용 userInfo
            let userInfo: [String: Any] = [
                "matchId": match.id,
                "leagueId": fav.leagueId,
                "leagueName": fav.leagueName,
                "leagueRegion": fav.leagueRegion,
                "favTeamCode": fav.teamCode,
                "teamAId": match.teamA.id,
                "teamACode": match.teamA.code,
                "teamAName": match.teamA.name,
                "teamAImage": match.teamA.imageURL ?? "",
                "teamBId": match.teamB.id,
                "teamBCode": match.teamB.code,
                "teamBName": match.teamB.name,
                "teamBImage": match.teamB.imageURL ?? "",
                "startTimeISO": isoFormatter.string(from: match.startTime)
            ]

            let fireDate = match.startTime.addingTimeInterval(-TimeInterval(minutes * 60))
            if fireDate > now {
                let content = UNMutableNotificationContent()
                content.title = notificationTitle(teamName: fav.teamName, minutes: minutes)
                content.body = "vs \(opponent.name) · \(fav.leagueName)"
                content.sound = .default
                content.userInfo = userInfo

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
                // 즐겨찾기 추가 시점에 이미 알림 시간 이내 → 즉시 알림
                let content = UNMutableNotificationContent()
                content.title = "\(fav.teamName) 경기가 곧 시작됩니다!"
                content.body = "vs \(opponent.name) · \(fav.leagueName)"
                content.sound = .default
                content.userInfo = userInfo
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
