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
                historySelectorRow
                Divider()
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

    // MARK: - 연도 + 라운드 선택 (한 줄에 드롭다운 두 개)

    // 라벨 글자 수가 바뀔 때(예: "전체" → "Rounds 1-2 · Week 9 (10)") 캡슐(Liquid Glass) 크기가
    // 자연스럽게 커졌다 작아지게 하려면, iOS 26의 glassEffect는 반드시 GlassEffectContainer로
    // 감싸야 한다 — 컨테이너 없이 개별 .glassEffect()만 쓰면 모양 변화가 부드럽게 보간되지 않고
    // 뚝뚝 끊겨 보인다(애플 문서화된 동작, 실측으로도 확인: .animation()을 껐다 켜도 변화 없었음).
    @ViewBuilder
    private var historySelectorRow: some View {
        let row = HStack(spacing: 8) {
            yearMenu
            if !viewModel.availableHistoricalRounds.isEmpty {
                roundMenu
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))

        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { row }
        } else {
            row
        }
    }

    private var yearMenu: some View {
        Menu {
            ForEach(viewModel.historicalYears, id: \.self) { year in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.selectHistoricalYear(year)
                    }
                } label: {
                    if year == viewModel.selectedHistoricalYear {
                        Label(String(year), systemImage: "checkmark")
                    } else {
                        Text(String(year))
                    }
                }
            }
        } label: {
            MenuFilterLabel {
                Text(viewModel.selectedHistoricalYear.map(String.init) ?? "연도")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .tint(Color(.label))
    }

    private var roundMenu: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.selectedHistoricalRound = nil
                }
            } label: {
                if viewModel.selectedHistoricalRound == nil { Label("전체", systemImage: "checkmark") }
                else { Text("전체") }
            }
            ForEach(viewModel.availableHistoricalRounds) { round in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.selectedHistoricalRound = round.label
                    }
                } label: {
                    let text = "\(round.label) (\(round.matches.count))"
                    if round.label == viewModel.selectedHistoricalRound {
                        Label(text, systemImage: "checkmark")
                    } else {
                        Text(text)
                    }
                }
            }
        } label: {
            MenuFilterLabel {
                Text(viewModel.selectedHistoricalRound ?? "전체")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
        .tint(Color(.label))
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
