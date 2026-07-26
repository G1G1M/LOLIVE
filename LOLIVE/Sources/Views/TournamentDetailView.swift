//
//  TournamentDetailView.swift
//  LOLIVE
//

import SwiftUI

struct TournamentDetailView: View {
    let league: League

    @State private var viewModel: TournamentDetailViewModel

    init(league: League) {
        self.league = league
        self._viewModel = State(initialValue: TournamentDetailViewModel(league: league))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if viewModel.isLoading {
                LoadingView("전체 일정 불러오는 중...")
            } else if viewModel.loadFailed {
                ErrorRetryView { Task { await viewModel.load() } }
            } else {
                VStack(spacing: 0) {
                    // 연도 선택 (고정)
                    if !viewModel.tournaments.isEmpty {
                        yearSelector
                        Divider()
                    }

                    if !viewModel.hasTournamentStarted {
                        notStartedView
                    } else if viewModel.isLoadingHistoricalMatches {
                        LoadingView("경기 기록 불러오는 중...")
                    } else if viewModel.selectedRoundDateGroups.isEmpty && viewModel.tournamentMatches.isEmpty {
                        EmptyStateView("경기 데이터가 없습니다")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // rounds 있을 때만 라운드 칩 표시
                        if !viewModel.availableRounds.isEmpty {
                            roundSelector
                            Divider()
                        }
                        matchList
                    }
                }
            }
        }
        .navigationTitle(league.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .task { await viewModel.load() }
    }

    // MARK: - 연도 선택 (고정 헤더 - 선택해도 위치 이동 없음)

    private var yearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.tournaments) { tournament in
                    let year = String(tournament.startDate.prefix(4))
                    let isSelected = tournament.id == viewModel.selectedTournamentId
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectTournament(tournament)
                        }
                    } label: {
                        Text(year)
                            .font(.subheadline).fontWeight(isSelected ? .bold : .regular)
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor
                                        : Color(.secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 라운드 선택 (고정 헤더 - 선택해도 위치 이동 없음)

    private var roundSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableRounds, id: \.self) { round in
                    let isSelected = round == viewModel.selectedRound
                    let count = viewModel.tournamentMatches.filter { $0.blockName == round }.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedRound = round
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(round)
                                .font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                            Text("\(count)")
                                .font(.caption2).fontWeight(.medium)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25)
                                            : Color(.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(isSelected ? Color.accentColor
                                    : Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 경기 목록 (날짜별 섹션)

    private var matchList: some View {
        Group {
            if viewModel.selectedRoundDateGroups.isEmpty {
                EmptyStateView("경기 데이터가 없습니다")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(viewModel.selectedRoundDateGroups) { group in
                            Section {
                                VStack(spacing: 6) {
                                    ForEach(group.matches) { match in
                                        NavigationLink(value: match) {
                                            MatchCardView(match: match, isLive: false, showDate: true)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 16)
                                    }
                                }
                                .padding(.vertical, 8)
                            } header: {
                                dateHeader(group.date)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                // 라운드 또는 연도 바뀔 때 스크롤 위치 맨 위로 리셋
                .id(viewModel.selectedTournamentId + (viewModel.selectedRound ?? ""))
            }
        }
    }

    private func dateHeader(_ date: Date) -> some View {
        HStack {
            Text(fullDateStr(date))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 시작 전

    private var notStartedView: some View {
        VStack(spacing: 20) {
            CachedAsyncImage(url: URL(string: league.imageURL ?? ""))
                .frame(width: 72, height: 72)
            VStack(spacing: 6) {
                Text("\(viewModel.selectedYear) \(league.name)")
                    .font(.title3).fontWeight(.bold)
                Text("아직 시작 전입니다")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let t = viewModel.selectedTournament {
                    Text("시작일  \(formatDate(t.startDate))")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func fullDateStr(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 (EEE)"
        return f.string(from: date)
    }

    private func formatDate(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return dateStr }
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy년 M월 d일"
        return fmt.string(from: date)
    }

}

#Preview {
    NavigationStack {
        TournamentDetailView(
            league: League(id: "98767991295297", slug: "worlds", name: "Worlds",
                           region: "국제 대회", imageURL: nil)
        )
    }
    .preferredColorScheme(.dark)
}
