//
//  LogoBadgeView.swift
//  LOLIVE
//
//  팀/리그 로고 공용 컴포넌트. 로고 원본 PNG가 흰색/검정 단색 위주인 경우 라이트·다크
//  모드 배경에 따라 로고가 안 보일 수 있어서, 모든 로고에 검정 그림자 + 흰색 그림자를
//  동시에 살짝 얹어 입체감을 준다. 판단 로직 없이 전 로고에 동일하게 적용하기 때문에
//  특정 로고만 다르게 처리된 느낌 없이, 흰 로고는 검정 그림자로 어두운 배경에서 살짝
//  도드라지고 검정 로고는 흰 그림자로 밝은 배경에서 살짝 도드라진다. 색이 있는 로고는
//  그림자가 거의 티 안 나게 얹혀서 원래 디자인 그대로 보인다.
//

import SwiftUI

struct LogoBadgeView: View {
    let imageURL: String?
    var size: CGFloat = 36

    private var shadowRadius: CGFloat { max(0.75, size * 0.04) }
    private var shadowOffset: CGFloat { max(0.4, size * 0.018) }

    var body: some View {
        CachedAsyncImage(url: URL(string: imageURL ?? ""))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: shadowRadius, x: shadowOffset, y: shadowOffset)
            .shadow(color: .white.opacity(0.35), radius: shadowRadius, x: -shadowOffset, y: -shadowOffset)
    }
}

#Preview {
    HStack(spacing: 20) {
        LogoBadgeView(imageURL: nil, size: 48)
        LogoBadgeView(imageURL: nil, size: 48)
    }
    .padding()
}
