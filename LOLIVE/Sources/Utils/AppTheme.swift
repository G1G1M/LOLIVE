//
//  AppTheme.swift
//  LOLIVE
//

import SwiftUI

/// 앱이 실행되는 동안 딱 한 번만 "진짜" 시스템 다크모드 여부를 읽어서 캐싱해둔다.
/// preferredColorScheme로 라이트/다크를 한 번이라도 강제 적용하고 나면 UIScreen의
/// 트레잇 값도 함께 오염돼서(실측 확인) 그 이후엔 시스템 값을 다시 읽어도 정확하지
/// 않을 수 있음 — 오버라이드가 걸리기 전, 앱이 막 시작된 시점의 값을 계속 재사용한다.
enum SystemAppearance {
    static let isDark: Bool = UIScreen.main.traitCollection.userInterfaceStyle == .dark
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "시스템 기본"
        case .light:  return "라이트"
        case .dark:   return "다크"
        }
    }

    /// "시스템 기본"도 nil이 아니라 항상 구체적인 라이트/다크 값으로 계산한다.
    /// .preferredColorScheme(nil)은 라이트/다크처럼 값이 있던 상태에서 시스템 기본으로
    /// 바뀔 때 이미 떠 있는 시트의 리렌더링이 멈춰버리는 경우가 있었음(실측 확인).
    var resolvedColorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark:  return .dark
        case .system: return SystemAppearance.isDark ? .dark : .light
        }
    }
}
