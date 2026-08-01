//
//  PushNotificationService.swift
//  LOLIVE
//

import Foundation
import FirebaseMessaging
import FirebaseFunctions
import os

/// 기기의 FCM 푸시 토큰을 즐겨찾기 팀 코드와 함께 서버(registerDeviceToken Cloud Function)에
/// 등록한다. 앱이 백그라운드/종료 상태여도 서버(syncLive)가 경기 시작·세트 변경·경기 종료를
/// 감지하면 이 토큰으로 원격 푸시를 보내준다 — 기존 MatchNotificationService(로컬 알림, 앱이
/// 켜져 있을 때만 동작)를 대체하는 게 아니라 보완하는 별도 경로.
@MainActor
final class PushNotificationService: NSObject, MessagingDelegate {
    static let shared = PushNotificationService()

    private let logger = Logger(subsystem: "com.lolive", category: "PushNotification")
    private var latestFavoriteTeamCodes: [String] = []

    private override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    /// 즐겨찾기가 바뀔 때마다 호출 — 이미 발급된 FCM 토큰이 있으면 최신 즐겨찾기로 즉시 재등록
    func updateFavoriteTeamCodes(_ codes: [String]) {
        latestFavoriteTeamCodes = codes
        if let token = Messaging.messaging().fcmToken {
            register(token: token)
        }
    }

    /// Firebase가 FCM 토큰을 (재)발급할 때마다 호출됨 — 앱 첫 실행, 토큰 갱신, 재설치 등
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            self.register(token: fcmToken)
        }
    }

    private func register(token: String) {
        let codes = latestFavoriteTeamCodes
        Task {
            do {
                let functions = Functions.functions(region: "asia-northeast3")
                _ = try await functions.httpsCallable("registerDeviceToken").call([
                    "token": token,
                    "favoriteTeamCodes": codes,
                ])
                logger.debug("✅ [Push] 기기 토큰 등록 완료 (즐겨찾기 \(codes.count)개)")
            } catch {
                logger.error("⚠️ [Push] 기기 토큰 등록 실패: \(error.localizedDescription)")
            }
        }
    }
}
