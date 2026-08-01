//
//  AppDelegate.swift
//  LOLIVE
//

import UIKit
import FirebaseCore
import FirebaseMessaging

/// 백그라운드 푸시 알림(APNs)을 받으려면 FirebaseApp.configure()와 원격 알림 등록이
/// 앱 실행 초기에 필요한데, 이건 UIApplicationDelegate 콜백으로만 받을 수 있어서
/// SwiftUI App에 @UIApplicationDelegateAdaptor로 붙여서 쓴다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // 원격 푸시 등록 실패해도 기존 로컬 알림(MatchNotificationService)은 영향 없음
    }
}
