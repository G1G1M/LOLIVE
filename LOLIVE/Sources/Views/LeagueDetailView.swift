//
//  LeagueDetailView.swift
//  LOLIVE
//
//  리그 상세 화면의 코어 레이아웃 (탭 바 + 네비게이션).
//
//  [파일 구조] — 리팩토링 Phase 2에서 탭별로 분리
//    - LeagueDetailView.swift            코어 (탭 바, 네비게이션, 에러/로딩 상태)
//    - LeagueDetailView+Standings.swift  순위 탭
//    - LeagueDetailView+Schedule.swift   일정 탭 (목록 + 브라켓)
//    - LeagueDetailView+Teams.swift      팀 · 선수 탭
//
//  Extension에서 접근해야 하므로 viewModel은 internal로 선언되어 있다.
//

import SwiftUI

struct LeagueDetailView: View {
    let league: League

    @State var viewModel: LeagueDetailViewModel

    init(league: League) {
        self.league = league
        self._viewModel = State(initialValue: LeagueDetailViewModel(league: league))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if viewModel.isLoading {
                LoadingView()
            } else if viewModel.loadFailed {
                ErrorRetryView { Task { await viewModel.load() } }
            } else {
                VStack(spacing: 0) {
                    tabBar
                    Divider()
                    tabContent
                }
                // "기록" 탭처럼 진입 시마다 로딩→콘텐츠로 크기가 크게 바뀌는 탭이 섞여있으면,
                // 탭 전환에 크로스페이드를 걸었을 때 그 크기 변화까지 같이 묶여 밑줄/콘텐츠가
                // 위에서 아래로 나오는 것처럼 어색하게 보임 — 하단 메인 탭바와 동일한 이유로
                // 애니메이션을 꺼서 즉시 전환되도록 통일 (ContentView.swift 참고)
                .transaction(value: viewModel.selectedTab) { $0.disablesAnimations = true }
            }
        }
        .navigationTitle(league.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .navigationDestination(for: Team.self) { team in
            TeamDetailView(
                team: team,
                league: league,
                standing: viewModel.standings.first { $0.team.id == team.id }
            )
        }
        .navigationDestination(for: Player.self) { player in
            LeaguePlayerDetailView(player: player, league: league)
        }
        .task { await viewModel.load() }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(LeagueDetailViewModel.Tab.allCases, id: \.self) { tab in
                Button {
                    viewModel.selectedTab = tab
                } label: {
                    VStack(spacing: 0) {
                        Text(tab.title)
                            .font(.subheadline)
                            .fontWeight(viewModel.selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(viewModel.selectedTab == tab ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Tab Content

    /// 각 탭 콘텐츠는 기능별 Extension 파일에 정의되어 있다.
    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .standings: standingsContent   // +Standings.swift
        case .schedule:  scheduleContent    // +Schedule.swift
        case .teams:     teamsContent       // +Teams.swift
        case .players:   playersContent     // +Teams.swift
        case .history:   historyContent     // +History.swift
        }
    }
}
