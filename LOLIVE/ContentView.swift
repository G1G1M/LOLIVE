//
//  ContentView.swift
//  LOLIVE
//
//  Created by 김지원 on 5/15/26.
//

import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @Query private var favoriteTeams: [FavoriteTeam]
    @Environment(TodayViewModel.self) private var todayViewModel
    // App Group 저장소를 써서 위젯(Small)도 "대표 팀"을 읽을 수 있게 함 — 앱 자체 동작(틴트
    // 컬러)은 그대로, 저장 위치만 위젯과 공유되는 곳으로 옮긴 것.
    @AppStorage("primaryTeamCode", store: UserDefaults(suiteName: SharedDataService.appGroupId))
    private var primaryTeamCode: String = ""
    @State private var selectedTab = 0

    private var themeColor: Color {
        primaryTeamCode.isEmpty ? Color.accentColor : TeamTheme.color(for: primaryTeamCode)
    }

    var body: some View {
        tabs
        .tint(themeColor)
        // 탭 전환(특히 Search 원형 버튼 → 검색창 모핑) 애니메이션이 굼떠 보인다는 피드백으로
        // selectedTab이 바뀌는 트랜잭션 자체의 애니메이션을 꺼서 즉시 전환되게 함
        .transaction(value: selectedTab) { $0.disablesAnimations = true }
        .task {
            syncFavoritedTeamIds()
            todayViewModel.startLivePolling()   // favoritedTeams 설정 직후 시작
            SharedDataService.saveFavoriteTeams(favoriteTeams)
            WidgetCenter.shared.reloadAllTimelines()
            await MatchNotificationService.shared.requestPermission()
            await MatchNotificationService.shared.reschedule(for: favoriteTeams)
            PushNotificationService.shared.updateFavoriteTeamCodes(favoriteTeams.map { $0.teamCode })
        }
        .onChange(of: favoriteTeams) { _, newValue in
            syncFavoritedTeamIds()
            SharedDataService.saveFavoriteTeams(newValue)
            saveWidgetNextMatches()
            todayViewModel.syncLiveActivitiesNow()
            Task { await MatchNotificationService.shared.reschedule(for: newValue) }
            PushNotificationService.shared.updateFavoriteTeamCodes(newValue.map { $0.teamCode })
        }
        .onChange(of: todayViewModel.upcomingMatches) { _, _ in
            saveWidgetNextMatches()
        }
        .onChange(of: todayViewModel.liveMatches) { _, _ in
            saveWidgetNextMatches()
        }
    }

    /// iOS 18+에선 새 `Tab` 기반 API를 사용. iOS 26에서는 하단 탭바 자체도 자동으로 새
    /// 유리 재질로 바뀐다(별도 코드 불필요). Search 탭은 `role: .search`를 줘서 iOS 26에서
    /// 나머지 탭 캡슐과 분리된 원형 유리 버튼으로 따로 표시되게 함 (애플 표준 Search Role
    /// 탭바 스타일).
    /// iOS는 탭바에 최대 5개까지만 바로 보여주고 그 이상은 자동으로 "더보기"에 몰아넣는다
    /// (search role 탭도 이 5개 슬롯 중 하나를 차지함). 그래서 메인 탭은 4개(Today/Leagues/
    /// Standings/Players)까지만 유지하고, Favorites는 탭에서 빼서 Today 상단 별 아이콘으로 옮겼다.
    /// `.tabViewStyle(.sidebarAdaptable)`는 일부러 안 씀 — 아이패드 사이드바 지원은 생기지만,
    /// 그 대가로 검색 활성화 시 시스템이 검색창 옆에 "이전 탭으로 돌아가기"용 원형 홈 아이콘을
    /// 자동으로 붙여서(제거 불가) X 버튼과 기능이 겹쳐 혼란스러움. 기본 스타일에선 이 아이콘이
    /// 없고, 대신 X 버튼(검색 취소)을 누르면 Today 탭으로 직접 이동하도록 만들었다.
    /// 배포 타깃(17.6)을 지원해야 해서 iOS 17은 기존 `.tabItem` 방식으로 폴백한다.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("Today", systemImage: "house.fill", value: 0) { TodayView() }
                Tab("Leagues", systemImage: "trophy.fill", value: 1) { LeaguesView() }
                Tab("Standings", systemImage: "list.number", value: 2) { StandingsView() }
                Tab("Players", systemImage: "person.fill", value: 3) { PlayersView() }
                Tab(value: 4, role: .search) {
                    SearchView { selectedTab = 0 }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tag(0)
                    .tabItem { Label("Today", systemImage: "house.fill") }

                LeaguesView()
                    .tag(1)
                    .tabItem { Label("Leagues", systemImage: "trophy.fill") }

                StandingsView()
                    .tag(2)
                    .tabItem { Label("Standings", systemImage: "list.number") }

                PlayersView()
                    .tag(3)
                    .tabItem { Label("Players", systemImage: "person.fill") }

                SearchView { selectedTab = 0 }
                    .tag(4)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
        }
    }

    private func syncFavoritedTeamIds() {
        todayViewModel.favoritedTeams = Set(favoriteTeams.map {
            FavoritedTeamRef(teamId: $0.teamId, teamCode: $0.teamCode, leagueId: $0.leagueId)
        })
    }

    private func sharedMatchEntry(match: Match, teamCode: String, liveMatch: LiveMatch?) -> SharedNextMatch {
        let isTeamA = match.teamA.code.lowercased() == teamCode.lowercased()
        let opponent = isTeamA ? match.teamB : match.teamA
        return SharedNextMatch(
            opponentName: opponent.name,
            opponentCode: opponent.code,
            opponentImageURL: opponent.imageURL,
            startTime: match.startTime,
            // MatchCardView의 isEffectivelyLive와 동일한 이중 판정 — getLive 응답에만 의존하면
            // 라이브 폴링 중 순간적으로 getLive 목록에서 빠지는 경기가 위젯엔 "예정"으로 저장돼
            // 앱 화면(LIVE 배지)과 위젯이 서로 다른 상태를 보여주는 문제가 있었음.
            isLive: liveMatch != nil || match.state == .inProgress,
            leagueName: match.league.name,
            savedAt: Date(),
            myScore: isTeamA ? match.scoreA : match.scoreB,
            oppScore: isTeamA ? match.scoreB : match.scoreA,
            currentGame: liveMatch?.currentSet
        )
    }

    private func saveWidgetNextMatches() {
        let allMatches = todayViewModel.liveMatches.map { $0.match }
            + todayViewModel.todayMatches
            + todayViewModel.upcomingMatches

        var nextMatchMap: [String: SharedNextMatch] = [:]
        for fav in favoriteTeams {
            // 팀 코드만 보고 고르면 같은 조직의 1군/2군 팀(코드가 같음, 예: LCK 본 리그와 LCK
            // 챌린저스 둘 다 "KT")이 섞인 오늘의 전체 리그 경기 목록에서 엉뚱한 쪽(2군)이 먼저
            // 걸릴 수 있다(실측 확인) — 팀 ID가 정확히 일치하거나, 폴백으로 코드+리그가 둘 다
            // 일치할 때만 이 즐겨찾기 팀의 경기로 인정한다.
            guard let match = allMatches.first(where: {
                $0.teamA.id == fav.teamId || $0.teamB.id == fav.teamId ||
                (($0.teamA.code.lowercased() == fav.teamCode.lowercased() ||
                  $0.teamB.code.lowercased() == fav.teamCode.lowercased()) &&
                 $0.league.id == fav.leagueId)
            }) else { continue }
            let liveMatch = todayViewModel.liveMatches.first { $0.match.id == match.id }
            nextMatchMap[fav.teamCode.uppercased()] = sharedMatchEntry(match: match, teamCode: fav.teamCode, liveMatch: liveMatch)
        }

        // 즐겨찾기 여부와 무관하게 지금 라이브 중인 모든 팀도 스냅샷에 포함 —
        // 위젯 Extension이 이 스냅샷만으로 라이브 판정할 수 있게 해서 자체 API 재호출을 줄인다.
        for liveMatch in todayViewModel.liveMatches {
            for team in [liveMatch.match.teamA, liveMatch.match.teamB] {
                let key = team.code.uppercased()
                if nextMatchMap[key] == nil {
                    nextMatchMap[key] = sharedMatchEntry(match: liveMatch.match, teamCode: team.code, liveMatch: liveMatch)
                }
            }
        }

        SharedDataService.saveNextMatches(nextMatchMap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#Preview {
    ContentView()
        .environment(TodayViewModel())
}
