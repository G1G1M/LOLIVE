//
//  FavoritesView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(sort: \FavoriteTeam.addedAt, order: .reverse) private var favoriteTeams: [FavoriteTeam]
    @Query(sort: \FavoritePlayer.addedAt, order: .reverse) private var favoritePlayers: [FavoritePlayer]
    @Environment(\.modelContext) private var modelContext
    @Environment(TodayViewModel.self) private var todayViewModel
    @AppStorage("primaryTeamCode") private var primaryTeamCode: String = ""
    @State private var showingTeamSearch = false

    private var hasFavorites: Bool { !favoriteTeams.isEmpty || !favoritePlayers.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                // ── 커스텀 Large Title 헤더 ──────────────────────────
                Section {
                    // 빈 섹션 본문: 헤더만 렌더링
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("즐겨찾기")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color(.label))
                            .textCase(nil)
                        Spacer()
                        if hasFavorites {
                            Button {
                                showingTeamSearch = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title2)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

                // ── 즐겨찾기 없을 때 ─────────────────────────────────
                if !hasFavorites {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "star")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                            Text("즐겨찾기가 없습니다")
                                .font(.headline)
                            Text("팀이나 선수 상세 페이지에서\n별 버튼을 눌러 추가하세요")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button {
                                showingTeamSearch = true
                            } label: {
                                Text("팀 찾아보기")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .padding(.horizontal, 20).padding(.vertical, 10)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .listRowBackground(Color(.systemGroupedBackground))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                }

                // ── 팀 섹션 ──────────────────────────────────────────
                if !favoriteTeams.isEmpty {
                    Section("팀") {
                        ForEach(favoriteTeams) { fav in
                            NavigationLink {
                                TeamDetailView(team: fav.asTeam, league: fav.asLeague)
                            } label: {
                                teamRow(fav)
                            }
                            .contextMenu {
                                let isPrimary = fav.teamCode.uppercased() == primaryTeamCode.uppercased()
                                Button {
                                    primaryTeamCode = isPrimary ? "" : fav.teamCode
                                } label: {
                                    Label(
                                        isPrimary ? "대표 팀 해제" : "대표 팀으로 설정",
                                        systemImage: isPrimary ? "paintpalette" : "paintpalette.fill"
                                    )
                                }
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach {
                                let team = favoriteTeams[$0]
                                if team.teamCode.uppercased() == primaryTeamCode.uppercased() {
                                    primaryTeamCode = ""
                                }
                                modelContext.delete(team)
                            }
                        }
                    }
                }

                // ── 선수 섹션 ─────────────────────────────────────────
                if !favoritePlayers.isEmpty {
                    Section("선수") {
                        ForEach(favoritePlayers) { fav in
                            NavigationLink {
                                LeaguePlayerDetailView(player: fav.asPlayer, league: fav.asLeague)
                            } label: {
                                playerRow(fav)
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { modelContext.delete(favoritePlayers[$0]) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTeamSearch) {
                TeamSearchView()
            }
        }
    }

    // MARK: - Team Row

    private func teamRow(_ fav: FavoriteTeam) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: fav.teamImageURL ?? ""))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(fav.teamName)
                    .font(.subheadline).fontWeight(.semibold)
                Text(fav.leagueName)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if fav.teamCode.uppercased() == primaryTeamCode.uppercased() {
                Image(systemName: "paintpalette.fill")
                    .font(.caption)
                    .foregroundStyle(TeamTheme.color(for: fav.teamCode))
                    .padding(.trailing, 4)
            }

            if let live = liveInfo(for: fav) {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("LIVE")
                            .font(.caption2).fontWeight(.bold).foregroundStyle(.red)
                    }
                    Text(live.score)
                        .font(.caption).fontWeight(.semibold)
                    Text("Game \(live.game)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private struct LiveInfo {
        let score: String
        let game: Int
    }

    private func liveInfo(for fav: FavoriteTeam) -> LiveInfo? {
        guard let liveMatch = todayViewModel.liveMatches.first(where: {
            $0.match.teamA.code.lowercased() == fav.teamCode.lowercased() ||
            $0.match.teamB.code.lowercased() == fav.teamCode.lowercased()
        }) else { return nil }

        let isTeamA = liveMatch.match.teamA.code.lowercased() == fav.teamCode.lowercased()
        let myScore  = isTeamA ? liveMatch.match.scoreA : liveMatch.match.scoreB
        let oppScore = isTeamA ? liveMatch.match.scoreB : liveMatch.match.scoreA
        let oppCode  = isTeamA ? liveMatch.match.teamB.code : liveMatch.match.teamA.code
        return LiveInfo(score: "\(myScore) - \(oppScore)  vs \(oppCode)", game: liveMatch.currentSet)
    }

    // MARK: - Player Row

    private func playerRow(_ fav: FavoritePlayer) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: fav.playerImageURL ?? ""))
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(fav.summonerName)
                    .font(.subheadline).fontWeight(.semibold)
                HStack(spacing: 6) {
                    Text(fav.teamCode)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(fav.leagueName)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(roleLabel(fav.role))
                .font(.caption2).fontWeight(.bold)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(roleColor(fav.role).opacity(0.2))
                .foregroundStyle(roleColor(fav.role))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func roleLabel(_ role: String) -> String {
        switch role.lowercased() {
        case "top":              return "TOP"
        case "jungle":           return "JGL"
        case "mid":              return "MID"
        case "bottom", "bot":    return "BOT"
        case "support":          return "SUP"
        default:                 return role.uppercased()
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role.lowercased() {
        case "top":              return .orange
        case "jungle":           return .green
        case "mid":              return .blue
        case "bottom", "bot":    return .red
        case "support":          return .purple
        default:                 return .secondary
        }
    }
}

#Preview {
    FavoritesView()
        .preferredColorScheme(.dark)
}
