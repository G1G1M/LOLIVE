//
//  StateViews.swift
//  LOLIVE
//
//  로딩 실패 · 빈 데이터 상태를 표시하는 공통 컴포넌트.
//
//  기존에 7개 뷰(LeaguesView, StandingsView, PlayersView, LeagueDetailView,
//  TeamDetailView, TeamSearchView, TournamentDetailView)에 중복 구현되어 있던
//  에러/빈 상태 UI를 하나로 통일했다.
//

import SwiftUI

// MARK: - 에러 + 재시도

/// 데이터 로드 실패 시 표시하는 전체 화면 에러 뷰.
/// "다시 시도" 버튼을 누르면 retry 클로저가 실행된다.
struct ErrorRetryView: View {
    let message: String
    let retry: () -> Void

    init(_ message: String = "데이터를 불러올 수 없습니다", retry: @escaping () -> Void) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("다시 시도", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 빈 상태

/// 데이터가 없을 때 표시하는 빈 상태 뷰.
/// 리스트/탭 내부에 인라인으로 배치할 수 있도록 세로 패딩만 갖는다.
struct EmptyStateView: View {
    let message: String
    let icon: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        _ message: String,
        icon: String = "exclamationmark.circle",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline).fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Preview

#Preview("ErrorRetryView") {
    ErrorRetryView { }
}

#Preview("EmptyStateView") {
    EmptyStateView("데이터가 없습니다", icon: "gamecontroller")
}
