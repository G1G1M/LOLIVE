//
//  LeagueDetailView+History.swift
//  LOLIVE
//
//  리그 상세 화면의 기록(과거 시즌) 탭 — 서버(Firestore 백필 데이터)에서 조회.
//

import SwiftUI

extension LeagueDetailView {

    var historyContent: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingHistoricalYears {
                LoadingView()
            } else if viewModel.historicalYears.isEmpty {
                EmptyStateView(
                    "과거 시즌 기록이 아직 없습니다",
                    icon: "clock.arrow.circlepath"
                )
                .padding(.top, 60)
            } else {
                yearSelector
                Divider()
                historyMatchList
            }
        }
        .task {
            await viewModel.loadHistoricalYears()
        }
    }

    // MARK: - 연도 선택

    private var yearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.historicalYears, id: \.self) { year in
                    let isSelected = year == viewModel.selectedHistoricalYear
                    SelectableChip(isSelected: isSelected) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectHistoricalYear(year)
                        }
                    } label: {
                        Text(String(year))
                            .font(.subheadline).fontWeight(isSelected ? .bold : .regular)
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 경기 목록 (날짜별 그룹핑)

    private var historyMatchList: some View {
        ScrollView {
            if viewModel.isLoadingHistoricalMatches {
                LoadingView()
            } else if viewModel.historicalMatches.isEmpty {
                EmptyStateView("이 시즌의 경기 기록이 없습니다").padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(historyDayGroups) { dayGroup in
                        historyDayHeader(dayGroup.date)
                        ForEach(dayGroup.matches) { match in
                            NavigationLink(value: match) {
                                MatchCardView(match: match, isLive: false)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16).padding(.vertical, 4)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private struct HistoryDayGroup: Identifiable {
        let id: String
        let date: Date
        let matches: [Match]
    }

    private var historyDayGroups: [HistoryDayGroup] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: viewModel.historicalMatches) { cal.startOfDay(for: $0.startTime) }
        return byDay.keys.sorted().map { day in
            HistoryDayGroup(
                id: "\(day.timeIntervalSince1970)",
                date: day,
                matches: byDay[day]!.sorted { $0.startTime < $1.startTime }
            )
        }
    }

    private func historyDayHeader(_ date: Date) -> some View {
        HStack {
            Text(date, style: .date)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
    }
}
