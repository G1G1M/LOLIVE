//
//  SelectableChip.swift
//  LOLIVE
//
//  선택형 필터 캡슐 칩의 공통 껍데기(버튼+패딩+배경+캡슐) — StandingsView(leagueChip),
//  PlayersView(filterChip), TournamentDetailView(연도/라운드 선택), LeagueDetailView+History(연도 선택),
//  LeagueDetailView+Schedule(목록/브라켓 토글)에 각각 따로 구현되어 있던 버튼 래핑 로직을 통일했다.
//  내부 라벨(아이콘·텍스트·서브 배지 등)은 화면마다 다르므로 그대로 커스터마이즈할 수 있게
//  ViewBuilder로 남겨둔다.
//
//  iOS 26 이상은 애플 기본 리퀴드 글래스(glassEffect)로, 미만은 기존 단색 캡슐로 표시한다.
//  GlassEffectContainer는 일부러 안 씀 — TodayView 필터 필과 같은 이유로, 이 칩들은 전부
//  "여러 개 중 하나만 고르는" 배타적 선택지라 서로 액체처럼 이어져 보이면 오히려 헷갈린다.
//

import SwiftUI

struct SelectableChip<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label().padding(.horizontal, 14).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .glassEffect(
                isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                in: Capsule()
            )
        } else {
            Button(action: action) {
                label()
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
