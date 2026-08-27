//
//  TodayView.swift
//  LOLIVE
//

import SwiftUI

struct TodayView: View {
    @Environment(TodayViewModel.self) var viewModel
    @State private var showMenu = false
    @State private var showFavorites = false
    @State var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State var showLiveOnly = false

    let cal = Calendar.current

    // 과거 5일 ~ upcoming 마지막 경기 날짜 (없으면 +5일)
    var dateRange: [Date] {
        let today = cal.startOfDay(for: Date())
        let lastUpcomingDay = viewModel.upcomingMatches.last.map { cal.startOfDay(for: $0.startTime) }
        let minEnd = cal.date(byAdding: .day, value: 5, to: today)!
        let end = max(lastUpcomingDay ?? minEnd, minEnd)
        let endDays = cal.dateComponents([.day], from: today, to: end).day ?? 5
        return (-5...endDays).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                titleHeader
                dateStrip
                favoritesToggle

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                    if viewModel.isLoading && viewModel.todayMatches.isEmpty {
                        LoadingView()
                    } else if viewModel.errorMessage != nil {
                        ErrorRetryView(viewModel.errorMessage ?? "데이터를 불러올 수 없습니다") {
                            Task { await viewModel.loadTodayMatches() }
                        }
                    } else {
                        matchList
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showMenu) { AppMenuView().sheetGrabber() }
            .sheet(isPresented: $showFavorites) {
                NavigationStack {
                    FavoritesView()
                        .navigationDestination(for: Match.self) { match in
                            MatchDetailView(match: match)
                        }
                        .navigationDestination(for: League.self) { league in
                            if league.isInternationalTournament {
                                TournamentDetailView(league: league)
                            } else {
                                LeagueDetailView(league: league)
                            }
                        }
                }
                .sheetGrabber()
            }
            // Match.self/League.self는 탭 루트에서 한 번씩만 등록 — 이 화면 안에서 중첩된
            // LeagueDetailView/TeamDetailView 등이 각자 또 등록하면 중복돼서 뒤로가기 시 화면이
            // 통째로 다시 만들어지는 버그가 있었다(실측 확인, 자세한 내용은 LeagueDetailView.swift
            // /MatchDetailView.swift 주석 참고).
            .navigationDestination(for: Match.self) { match in
                MatchDetailView(
                    match: match,
                    liveMatch: viewModel.liveMatches.first { $0.match.id == match.id }
                )
            }
            .navigationDestination(for: League.self) { league in
                if league.isInternationalTournament {
                    TournamentDetailView(league: league)
                } else {
                    LeagueDetailView(league: league)
                }
            }
        }
        .task {
            await viewModel.loadTodayMatches()
        }
    }

    // MARK: - Fixed: Title

    private var titleHeader: some View {
        HStack {
            Text("오늘의 경기")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(.label))
            Spacer()
            Button { showFavorites = true } label: {
                Image(systemName: "star")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .frame(width: 36, height: 36)
            }
            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(.label))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Color(.systemGroupedBackground))
    }

}

#Preview {
    TodayView()
        .environment(TodayViewModel())
        .preferredColorScheme(.dark)
}
