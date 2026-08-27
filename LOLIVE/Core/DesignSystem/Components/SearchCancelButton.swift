//
//  SearchCancelButton.swift
//  LOLIVE
//
//  검색창이 포커스됐을 때 옆에 나타나는 원형 취소(X) 버튼. GlassFieldBackground/
//  MenuFilterLabel과 동일한 규칙으로 iOS 26 이상에서는 Liquid Glass(.glassEffect),
//  미만에서는 일반 배경색 원형으로 표시한다.
//

import SwiftUI

struct SearchCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let icon = Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)

            if #available(iOS 26.0, *) {
                icon.glassEffect(.regular.interactive(), in: Circle())
            } else {
                icon.background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
        }
        .buttonStyle(.plain)
    }
}
