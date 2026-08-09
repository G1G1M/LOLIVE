//
//  LeaguesView.swift
//  LOLIVE
//
//  리그 탭 메인 화면. 지역별로 그룹핑된 리그 목록을 표시한다.
//  데이터 로드/필터/그룹핑 로직은 LeaguesViewModel 담당 (리팩토링 Phase 2).
//

import SwiftUI

struct LeaguesView: View {

    @State private var viewModel = LeaguesViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                titleHeader
                searchBar

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if viewModel.isLoading && viewModel.leagues.isEmpty {
                        LoadingView()
                    } else if viewModel.loadFailed && viewModel.leagues.isEmpty {
                        ErrorRetryView { Task { await viewModel.load() } }
                    } else {
                        leagueList
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // 진짜 네이티브 .searchable(iOS 26 리퀴드 글래스 자동 적용)은 시스템 타이틀에만
            // 붙어서, 커스텀 타이틀(오늘의 경기/순위와 동일 스타일)을 쓰면 위쪽 여백이 iOS 26
            // 새 네비게이션 바 디자인 때문에 훨씬 커진다(실측 확인). 여백을 줄이는 조합도
            // 여럿 시도함:
            //  - 큰 타이틀(.large) + searchable: 여백 큼, 폰트를 줄여도 안 줄어듦
            //  - 인라인 + 시스템 기본 타이틀(가운데 정렬, 작은 글씨) + searchable: 여백 줄고
            //    정상 작동하지만 가운데 정렬/작은 폰트라 스타일이 안 맞음
            //  - 인라인 + leading 커스텀 뷰(왼쪽 정렬 시도, .navigationBarLeading/.topBarLeading
            //    둘 다) + searchable: iOS 26이 타이틀을 "..." 축약 버튼으로 바꿔버림(재현됨)
            //  - 인라인 + principal 커스텀 뷰 + searchable: 가운데 정렬로 강제됨
            //  - UIKit UISearchController 브릿지(UIViewControllerRepresentable): 여백/검색
            //    다 되지만 NavigationLink가 중첩 UIHostingController를 못 넘을 위험 있어 보류
            // "여백 줄이기 + 왼쪽정렬 유지 + 진짜 searchable" 셋 다 동시에 만족하는 조합을
            // 못 찾아서, 커스텀 검색창에 .glassEffect만 입혀 겉모습은 동일하게, 스타일은
            // 오늘의 경기/순위와 통일된 상태를 유지한다(GlassFieldBackground).
            .navigationDestination(for: League.self) { league in
                // Worlds/MSI는 연도별 히스토리가 있는 TournamentDetailView로 분기
                if league.isInternationalTournament {
                    TournamentDetailView(league: league)
                } else {
                    LeagueDetailView(league: league)
                }
            }
            // Match.self는 여기서 한 번만 등록 — LeagueDetailView/TeamDetailView 등 중첩 화면에서
            // 또 등록하면 중복돼서 뒤로가기 시 화면이 다시 만들어지는 버그가 있었다(실측 확인).
            .navigationDestination(for: Match.self) { match in
                MatchDetailView(match: match)
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - 헤더

    private var titleHeader: some View {
        HStack {
            Text("리그")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(.label))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Color(.systemGroupedBackground))
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            GlassFieldBackground {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("리그 검색", text: $viewModel.searchText)
                        .font(.subheadline)
                        .focused($isSearchFocused)
                    if !viewModel.searchText.isEmpty {
                        Button { viewModel.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if isSearchFocused {
                SearchCancelButton {
                    viewModel.searchText = ""
                    isSearchFocused = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 리스트

    private var leagueList: some View {
        List {
            ForEach(viewModel.grouped, id: \.region) { group in
                Section {
                    ForEach(group.leagues) { league in
                        NavigationLink(value: league) {
                            leagueRow(league, isInternational: group.region == "국제 대회")
                        }
                    }
                } header: {
                    if group.region == "국제 대회" {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.0))
                            Text(group.region)
                                .textCase(nil)
                        }
                    } else {
                        Text(group.region)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func leagueRow(_ league: League, isInternational: Bool = false) -> some View {
        HStack(spacing: 12) {
            LogoBadgeView(imageURL: league.imageURL, size: 36)

            Text(league.name)
                .font(.subheadline)
                .fontWeight(isInternational ? .semibold : .medium)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LeaguesView()
        .preferredColorScheme(.dark)
}
