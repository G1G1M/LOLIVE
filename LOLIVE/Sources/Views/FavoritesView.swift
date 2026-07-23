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

    // iOS가 하단 탭 6개 중 5·6번째(Favorites/Search)를 자동으로 "더보기"로 묶는데,
    // "더보기" 목록 자체가 이미 UINavigationController를 제공하므로 여기서 NavigationStack을
    // 또 씌우면 백버튼이 2개(더보기 것 + 이 화면 것) 겹쳐 보인다. 그래서 NavigationStack 없이
    // "더보기"가 제공하는 네비게이션 컨텍스트에 NavigationLink를 바로 얹는다.
    var body: some View {
        List {
                // ── 즐겨찾기 없을 때 ─────────────────────────────────
                if !hasFavorites {
                    Section {
                        EmptyStateView(
                            "즐겨찾기가 없습니다\n팀이나 선수 상세 페이지에서 별 버튼을 눌러 추가하세요",
                            icon: "star",
                            actionTitle: "팀 찾아보기"
                        ) {
                            showingTeamSearch = true
                        }
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("즐겨찾기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasFavorites {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTeamSearch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingTeamSearch) {
            TeamSearchView()
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
            PlayerAvatarView(imageURL: fav.playerImageURL, size: 36)

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
            } else {
                Text(roleLabel(fav.role))
                    .font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(roleColor(fav.role).opacity(0.2))
                    .foregroundStyle(roleColor(fav.role))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func liveInfo(for fav: FavoritePlayer) -> LiveInfo? {
        guard let liveMatch = todayViewModel.liveMatches.first(where: {
            $0.match.teamA.code.lowercased() == fav.teamCode.lowercased() ||
            $0.match.teamB.code.lowercased() == fav.teamCode.lowercased()
        }) else { return nil }

        let isTeamA  = liveMatch.match.teamA.code.lowercased() == fav.teamCode.lowercased()
        let myScore  = isTeamA ? liveMatch.match.scoreA : liveMatch.match.scoreB
        let oppScore = isTeamA ? liveMatch.match.scoreB : liveMatch.match.scoreA
        let oppCode  = isTeamA ? liveMatch.match.teamB.code : liveMatch.match.teamA.code
        return LiveInfo(score: "\(myScore) - \(oppScore)  vs \(oppCode)", game: liveMatch.currentSet)
    }

    // MARK: - Helpers

    private func roleLabel(_ role: String) -> String { RoleStyle.label(role) }
    private func roleColor(_ role: String) -> Color  { RoleStyle.color(role) }
}

#Preview {
    FavoritesView()
        .preferredColorScheme(.dark)
}
