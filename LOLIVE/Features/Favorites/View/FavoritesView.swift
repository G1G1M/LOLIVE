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
    // App Group 저장소 — ContentView.swift와 동일한 이유(위젯 Small이 읽을 수 있게)
    @AppStorage("primaryTeamCode", store: UserDefaults(suiteName: SharedDataService.appGroupId))
    private var primaryTeamCode: String = ""
    @State private var showingTeamSearch = false
    @State private var showLiveOnly = false

    private var hasFavorites: Bool { !favoriteTeams.isEmpty || !favoritePlayers.isEmpty }

    private var displayedFavoriteTeams: [FavoriteTeam] {
        guard showLiveOnly else { return favoriteTeams }
        return favoriteTeams.filter { liveInfo(teamCode: $0.teamCode) != nil }
    }

    private var displayedFavoritePlayers: [FavoritePlayer] {
        guard showLiveOnly else { return favoritePlayers }
        return favoritePlayers.filter { liveInfo(teamCode: $0.teamCode) != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasFavorites { liveFilterBar }

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
                } else if showLiveOnly && displayedFavoriteTeams.isEmpty && displayedFavoritePlayers.isEmpty {
                    Section {
                        EmptyStateView(
                            "현재 라이브 중인 즐겨찾기 경기가 없습니다",
                            icon: "dot.radiowaves.left.and.right"
                        )
                        .listRowBackground(Color(.systemGroupedBackground))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    // ── 팀 섹션 ──────────────────────────────────────────
                    if !displayedFavoriteTeams.isEmpty {
                        Section("팀") {
                            ForEach(displayedFavoriteTeams) { fav in
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
                                    let team = displayedFavoriteTeams[$0]
                                    if team.teamCode.uppercased() == primaryTeamCode.uppercased() {
                                        primaryTeamCode = ""
                                    }
                                    modelContext.delete(team)
                                }
                            }
                        }
                    }

                    // ── 선수 섹션 ─────────────────────────────────────────
                    if !displayedFavoritePlayers.isEmpty {
                        Section("선수") {
                            ForEach(displayedFavoritePlayers) { fav in
                                NavigationLink {
                                    LeaguePlayerDetailView(player: fav.asPlayer, league: fav.asLeague)
                                } label: {
                                    playerRow(fav)
                                }
                            }
                            .onDelete { indexSet in
                                indexSet.forEach { modelContext.delete(displayedFavoritePlayers[$0]) }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .navigationTitle("즐겨찾기")
        .navigationBarTitleDisplayMode(.inline)
        .sheetCloseButton()
        .toolbar {
            // 닫기가 오른쪽 위로 고정됐으므로 부가 액션은 왼쪽으로 보낸다.
            if hasFavorites {
                ToolbarItem(placement: .topBarLeading) {
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
                .sheetGrabber()
        }
    }

    // MARK: - Live Filter Bar

    private var liveFilterLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(showLiveOnly ? Color.white : Color.red)
                .frame(width: 6, height: 6)
            Text("LIVE")
        }
        .font(.subheadline).fontWeight(.semibold)
        .foregroundStyle(showLiveOnly ? Color.white : Color.secondary)
    }

    @ViewBuilder
    private var liveFilterBar: some View {
        HStack(spacing: 8) {
            if #available(iOS 26.0, *) {
                Button { showLiveOnly.toggle() } label: {
                    liveFilterLabel.padding(.horizontal, 14).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    showLiveOnly ? .regular.tint(.red).interactive() : .regular.interactive(),
                    in: Capsule()
                )
            } else {
                Button { showLiveOnly.toggle() } label: {
                    liveFilterLabel
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(showLiveOnly ? Color.red : Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.15), value: showLiveOnly)
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

            if let live = liveInfo(teamCode: fav.teamCode) {
                VStack(alignment: .trailing, spacing: 3) {
                    LiveBadge(animated: false)
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

    /// getLive 목록에서 먼저 찾고, 없으면(일부 대회는 실시간 API 응답이 비어있음)
    /// 오늘 스케줄 상 상태가 inProgress인 경기로 대체 판정한다.
    private func liveInfo(teamCode: String) -> LiveInfo? {
        if let liveMatch = todayViewModel.liveMatches.first(where: {
            $0.match.teamA.code.lowercased() == teamCode.lowercased() ||
            $0.match.teamB.code.lowercased() == teamCode.lowercased()
        }) {
            return liveInfo(match: liveMatch.match, teamCode: teamCode, game: liveMatch.currentSet)
        }
        if let match = todayViewModel.todayMatches.first(where: {
            $0.state == .inProgress &&
            ($0.teamA.code.lowercased() == teamCode.lowercased() || $0.teamB.code.lowercased() == teamCode.lowercased())
        }) {
            return liveInfo(match: match, teamCode: teamCode, game: 1)
        }
        return nil
    }

    private func liveInfo(match: Match, teamCode: String, game: Int) -> LiveInfo {
        let isTeamA  = match.teamA.code.lowercased() == teamCode.lowercased()
        let myScore  = isTeamA ? match.scoreA : match.scoreB
        let oppScore = isTeamA ? match.scoreB : match.scoreA
        let oppCode  = isTeamA ? match.teamB.code : match.teamA.code
        return LiveInfo(score: "\(myScore) - \(oppScore)  vs \(oppCode)", game: game)
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

            if let live = liveInfo(teamCode: fav.teamCode) {
                VStack(alignment: .trailing, spacing: 3) {
                    LiveBadge(animated: false)
                    Text(live.score)
                        .font(.caption).fontWeight(.semibold)
                    Text("Game \(live.game)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                RoleBadge(role: fav.role)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FavoritesView()
        .preferredColorScheme(.dark)
}
