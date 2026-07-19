//
//  LoadingView.swift
//  LOLIVE
//

import SwiftUI

/// 전체화면 로딩 인디케이터 — 0.1초 딜레이 후 페이드인 (캐시 즉시 로드 시 깜빡임 방지)
struct LoadingView: View {
    let message: String
    @State private var appeared = false

    init(_ message: String = "불러오는 중...") {
        self.message = message 
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.3)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3).delay(0.1)) {
                appeared = true
            }
        }
    }
}
