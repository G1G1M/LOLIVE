//
//  SheetPresentation.swift
//  LOLIVE
//
//  시트(모달) 공통 표현.
//
//  [왜 한 곳에 모으나] 호출부마다 `.presentationDragIndicator(.visible)`를 직접 붙이면
//  새 시트를 추가할 때 빠뜨리기 쉽다. 시트 표현을 바꿀 일이 생기면(예: detents 추가)
//  여기 하나만 고치면 전부 따라온다.
//

import SwiftUI

extension View {

    /// 시트 상단 가운데에 그래버(끌어서 내리거나 크기를 바꿀 수 있다는 표시)를 보이게 한다.
    ///
    /// 앱의 모든 시트에 붙인다 — 시트가 끌어서 닫히는 화면이라는 걸 알려주는 표준 요소라,
    /// 어떤 시트에선 보이고 어떤 시트에선 안 보이면 오히려 조작 방법을 헷갈리게 만든다.
    /// (`fullScreenCover`나 네비게이션 푸시로 여는 화면엔 해당 없음 — 그쪽은 닫기 버튼을 쓴다)
    func sheetGrabber() -> some View {
        presentationDragIndicator(.visible)
    }
}
