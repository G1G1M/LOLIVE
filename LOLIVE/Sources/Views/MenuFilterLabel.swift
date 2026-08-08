//
//  MenuFilterLabel.swift
//  LOLIVE
//
//  Menu(드롭다운 필터) 버튼의 라벨 공용 컴포넌트. SelectableChip과 동일한 규칙으로
//  iOS 26 이상에서는 Liquid Glass(.glassEffect), 미만에서는 캡슐 배경으로 표시한다.
//

import SwiftUI

struct MenuFilterLabel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let inner = HStack(spacing: 6) {
            content()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)

        if #available(iOS 26.0, *) {
            inner.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            inner.background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
    }
}
