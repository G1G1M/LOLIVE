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
            // 탭을 처음 누른 프레임엔 .task가 아직 시작 전이라 isLoadingHistoricalYears가 false인
            // 채로 한 프레임 렌더링됨 — hasAttemptedHistoricalLoad로 "로딩 시작 전"도 로딩 취급해서
            // "빈 화면 → 스피너 → 목록" 3단 점프(위→아래로 미끄러지는 것처럼 보이던 원인) 방지.
            if !viewModel.hasAttemptedHistoricalLoad || viewModel.isLoadingHistoricalYears {
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
                if !viewModel.availableHistoricalRounds.isEmpty {
                    roundSelector
                    Divider()
                }
                historyMatchList
            }
        }
        // 다른 탭은 진입 시 이미 데이터가 로드돼있어 탭 전환 애니메이션(부모의
        // .animation(value: selectedTab))이 자연스럽게 적용되지만, 이 탭만 진입할 때마다
        // 로딩 스피너 → 실제 목록으로 크기가 크게 바뀌는 별도 전환이 하나 더 있음. 이 전환까지
        // 부모의 탭 전환 애니메이션에 같이 걸리면서 "위에서 내려오는" 것처럼 어색하게 보였음 —
        // 로딩 완료 시점의 전환만 애니메이션 없이 즉시 반영되도록 분리.
        .transaction { $0.animation = nil }
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

    // MARK: - 라운드 선택 (플레이오프/그룹 스테이지 등 — 연도 안에서 좁혀보기)

    private var roundSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let isAllSelected = viewModel.selectedHistoricalRound == nil
                SelectableChip(isSelected: isAllSelected) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.selectedHistoricalRound = nil
                    }
                } label: {
                    Text("전체")
                        .font(.subheadline).fontWeight(isAllSelected ? .semibold : .regular)
                        .foregroundStyle(isAllSelected ? .white : .primary)
                }

                ForEach(viewModel.availableHistoricalRounds) { round in
                    let isSelected = round.label == viewModel.selectedHistoricalRound
                    SelectableChip(isSelected: isSelected) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedHistoricalRound = round.label
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(round.label)
                                .font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                            Text("\(round.matches.count)")
                                .font(.caption2).fontWeight(.medium)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.25)
                                            : Color(.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
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
        let matches: [Match]
        if let round = viewModel.selectedHistoricalRound,
           let group = viewModel.availableHistoricalRounds.first(where: { $0.label == round }) {
            matches = group.matches
        } else {
            matches = viewModel.historicalMatches
        }
        let cal = Calendar.current
        let byDay = Dictionary(grouping: matches) { cal.startOfDay(for: $0.startTime) }
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
