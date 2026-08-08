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
        GlassFieldBackground {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("리그 검색", text: $viewModel.searchText)
                    .font(.subheadline)
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
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
