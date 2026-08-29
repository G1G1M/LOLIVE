//
//  LiveBadge.swift
//  LOLIVE
//
//  LIVE 배지(빨간 점 + "LIVE" 텍스트) — MatchCardView/MatchDetailView의 깜빡이는 캡슐 배지와
//  FavoritesView의 애니메이션 없는 인라인 버전(2곳)에 각각 따로 구현되어 있던 걸 통일했다.
//

import SwiftUI

struct LiveBadge: View {
    /// true: 캡슐 배경 + 패딩 + 점 깜빡이는 애니메이션 (경기 카드/경기 상세 상태 배지)
    /// false: 배경 없는 인라인 점 + 텍스트만 (즐겨찾기 목록 행)
    var animated: Bool = true

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(animated && isPulsing ? 1.4 : 1.0)
                .animation(
                    animated ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
                    value: isPulsing
                )
                .onAppear { if animated { isPulsing = true } }
            Text("LIVE")
                .font(.caption).fontWeight(.bold).foregroundStyle(.red)
        }
        .padding(.horizontal, animated ? 10 : 0)
        .padding(.vertical, animated ? 4 : 0)
        .background(animated ? Color.red.opacity(0.15) : Color.clear)
        .clipShape(Capsule())
        // 깜빡이는 점과 "LIVE" 글자가 따로 읽히지 않도록 한 덩어리로 묶는다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("진행 중")
    }
}
