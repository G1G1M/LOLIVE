//
//  GlassFieldBackground.swift
//  LOLIVE
//
//  검색창처럼 캡슐형(완전히 둥근) 배경이 필요한 커스텀 입력 필드 공용 래퍼.
//  SelectableChip/MenuFilterLabel과 동일한 규칙으로 iOS 26 이상에서는
//  Liquid Glass(.glassEffect), 미만에서는 일반 배경색으로 표시한다.
//

import SwiftUI

struct GlassFieldBackground<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let inner = content()
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

        if #available(iOS 26.0, *) {
            inner.glassEffect(.regular, in: Capsule())
        } else {
            inner.background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
    }
}
