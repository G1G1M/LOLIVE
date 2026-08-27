//
//  RoleBadge.swift
//  LOLIVE
//
//  포지션 배지(TOP/JGL/MID/BOT/SUP) — FavoritesView, LeagueDetailView+Teams, LeaguePlayerDetailView,
//  PlayersView, TeamDetailView, SearchView 6곳에 각각 따로 구현되어 있던 동일한 캡슐 배지를 통일했다.
//

import SwiftUI

struct RoleBadge: View {
    let role: String

    var body: some View {
        Text(RoleStyle.label(role))
            .font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoleStyle.color(role).opacity(0.2))
            .foregroundStyle(RoleStyle.color(role))
            .clipShape(Capsule())
    }
}
