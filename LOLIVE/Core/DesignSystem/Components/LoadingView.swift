//
//  LoadingView.swift
//  LOLIVE
//

import SwiftUI

/// 로딩 인디케이터 — 0.1초 딜레이 후 페이드인 (캐시 즉시 로드 시 깜빡임 방지)
/// ZStack 등 화면 전체 크기가 주어지는 곳에서는 화면 정중앙에 표시된다.
/// ScrollView 안(탭별 섹션 로딩 등)에 놓이면 ScrollView가 자식에게 무한 높이를
/// 제안해서 maxHeight: .infinity만으로는 위쪽에 붙어버리기 때문에(실측 확인),
/// minHeight를 넉넉하게 줘서 그런 곳에서도 화면 가운데 근처에 오도록 통일한다.
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
        .frame(maxWidth: .infinity)
        .frame(minHeight: 400, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3).delay(0.1)) {
                appeared = true
            }
        }
    }
}
