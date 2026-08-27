//
//  TodayView+Filters.swift
//  LOLIVE
//
//  Today 화면의 전체 / 즐겨찾기 / LIVE 필터 필. 라디오 버튼처럼 하나만 선택된다.
//

import SwiftUI

extension TodayView {

    // MARK: - Fixed: Favorites Toggle

    /// Liquid Glass 시범 적용 지점 — iOS 26 미만은 기존 단색 캡슐 스타일 그대로 유지.
    /// GlassEffectContainer는 일부러 안 씀 — 서로 배타적으로 선택하는 필들이 눌릴 때 옆 필이랑
    /// 시각적으로 이어져 보여서(액체처럼 합쳐지는 효과) 헷갈릴 수 있음. 애플 가이드도 이 효과는
    /// "하나로 묶인 느낌이 필요한" 경우에 쓰라고 권장 — 지금처럼 독립적인 선택지엔 안 맞음.
    var favoritesToggle: some View {
        pillsRow
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            .animation(.easeInOut(duration: 0.15), value: viewModel.showFavoritesOnly)
            .animation(.easeInOut(duration: 0.15), value: showLiveOnly)
    }

    private var pillsRow: some View {
        HStack(spacing: 8) {
            filterPill(title: "전체", isSelected: !viewModel.showFavoritesOnly && !showLiveOnly) {
                viewModel.showFavoritesOnly = false
                showLiveOnly = false
            }
            if viewModel.hasFavoriteTeams {
                filterPill(title: "★ 즐겨찾기", isSelected: viewModel.showFavoritesOnly && !showLiveOnly) {
                    viewModel.showFavoritesOnly = true
                    showLiveOnly = false
                }
            }
            liveFilterPill
            Spacer()
        }
    }

    private func filterPillLabel(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.subheadline).fontWeight(.semibold)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
    }

    @ViewBuilder
    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        if #available(iOS 26.0, *) {
            Button(action: action) { filterPillLabel(title, isSelected: isSelected) }
                .buttonStyle(.plain)
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                    in: Capsule()
                )
        } else {
            Button(action: action) {
                filterPillLabel(title, isSelected: isSelected)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var liveFilterLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(showLiveOnly ? Color.white : Color.red)
                .frame(width: 6, height: 6)
            Text("LIVE")
        }
        .font(.subheadline).fontWeight(.semibold)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .foregroundStyle(showLiveOnly ? Color.white : Color.secondary)
    }

    @ViewBuilder
    private var liveFilterPill: some View {
        if #available(iOS 26.0, *) {
            Button {
                showLiveOnly = true
                viewModel.showFavoritesOnly = false
            } label: {
                liveFilterLabel
            }
            .buttonStyle(.plain)
            .glassEffect(
                showLiveOnly ? .regular.tint(.red).interactive() : .regular.interactive(),
                in: Capsule()
            )
        } else {
            Button {
                showLiveOnly = true
                viewModel.showFavoritesOnly = false
            } label: {
                liveFilterLabel
                    .background(showLiveOnly ? Color.red : Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
