//
//  SheetCloseButton.swift
//  LOLIVE
//
//  시트 닫기 버튼과 그 자리.
//
//  [왜 한 곳에 모으나] 예전엔 화면마다 제각각이었다 — 메뉴·선수 스탯·챔피언 상세·팀 스탯은
//  오른쪽 위(`.topBarTrailing`), 즐겨찾기·팀 검색은 왼쪽 위(`.cancellationAction`).
//  같은 "닫기"인데 시트마다 손이 가는 곳이 달라지면 매번 눈으로 찾아야 한다.
//
//  [규칙] 닫기는 **항상 오른쪽 위**. 부가 액션이나 장식은 왼쪽 위로 보낸다.
//  ("취소"가 아니라 "닫기"다 — 되돌릴 편집이 없는 읽기 전용 시트라 애플 관례도 trailing이다)
//

import SwiftUI

struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("닫기") { dismiss() }
    }
}

extension View {

    /// 시트 오른쪽 위에 닫기 버튼을 놓는다. 자리를 고정하는 게 목적이라
    /// 시트마다 직접 `ToolbarItem`을 쓰지 말고 이걸 쓸 것.
    func sheetCloseButton() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
        }
    }
}
