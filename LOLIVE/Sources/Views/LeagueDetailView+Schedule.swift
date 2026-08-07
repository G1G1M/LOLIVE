//
//  LeagueDetailView+Schedule.swift
//  LOLIVE
//
//  리그 상세 화면의 일정 탭.
//
//  [구성]
//  - 목록 모드: 날짜별 + blockName(라운드명)별로 그룹핑된 경기 리스트
//  - 브라켓 모드: 플레이오프 라운드를 가로 스크롤 토너먼트 표로 표시
//    (viewModel.isBracketAvailable이 true일 때만 토글 노출)
//

import SwiftUI

extension LeagueDetailView {

    // MARK: - 일정 탭 (래퍼: 토글 + 목록/브라켓 전환)

    var scheduleContent: some View {
        VStack(spacing: 0) {
            if viewModel.isBracketAvailable {
                scheduleToggle
                Divider()
            }
            if viewModel.showBracket {
                bracketContent
            } else {
                scheduleListContent
            }
        }
    }

    private var scheduleToggle: some View {
        HStack(spacing: 8) {
            scheduleToggleButton(title: "목록", sf: "list.bullet", selected: !viewModel.showBracket) {
                viewModel.showBracket = false
            }
            scheduleToggleButton(title: "브라켓", sf: "tablecells", selected: viewModel.showBracket) {
                viewModel.showBracket = true
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    private func scheduleToggleButton(title: String, sf: String, selected: Bool,
                                      action: @escaping () -> Void) -> some View {
        SelectableChip(isSelected: selected, action: action) {
            HStack(spacing: 5) {
                Image(systemName: sf).font(.system(size: 12))
                Text(title).font(.subheadline).fontWeight(selected ? .semibold : .regular)
            }
            .foregroundStyle(selected ? .white : .secondary)
        }
    }

    // MARK: - 브라켓 모드

    private var bracketContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(viewModel.bracketRounds.enumerated()), id: \.element.id) { idx, round in
                    bracketRoundColumn(round)

                    // 라운드 사이 화살표
                    if idx < viewModel.bracketRounds.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 36)
                            .frame(width: 20)
                    }
                }
            }
            .padding(16)
        }
    }

    private func bracketRoundColumn(_ round: LeagueDetailViewModel.BracketRound) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(round.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(round.matches) { match in
                    bracketMatchCard(match)
                }
            }
        }
        .frame(width: 184)
    }

    private func bracketMatchCard(_ match: Match) -> some View {
        NavigationLink(value: match) {
            VStack(spacing: 0) {
                bracketTeamRow(
                    team: match.teamA, score: match.scoreA,
                    won: match.state == .completed && match.scoreA > match.scoreB,
                    state: match.state
                )
                Divider().padding(.horizontal, 12)
                bracketTeamRow(
                    team: match.teamB, score: match.scoreB,
                    won: match.state == .completed && match.scoreB > match.scoreA,
                    state: match.state
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func bracketTeamRow(team: Team, score: Int, won: Bool, state: MatchState) -> some View {
        HStack(spacing: 8) {
            CachedAsyncImage(url: URL(string: team.imageURL ?? ""))
                .frame(width: 20, height: 20)
            Text(team.code)
                .font(.system(size: 13, weight: won ? .bold : .regular))
                .foregroundStyle(won ? Color(.label) : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if state == .completed {
                Text("\(score)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(won ? Color(.label) : .secondary)
                    .frame(width: 18, alignment: .trailing)
            } else {
                Text("-")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(won ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // MARK: - 목록 모드 그룹 구조

    /// 하루치 경기 묶음 (날짜 헤더 단위)
    struct DayGroup: Identifiable {
        let id: String
        let date: Date
        let blockGroups: [BlockGroup]
    }

    /// 같은 날 안에서 blockName(예: "플레이오프 R1")이 같은 연속 경기 묶음
    struct BlockGroup: Identifiable {
        let id: String
        let blockName: String?
        let matches: [Match]
    }

    /// 경기 목록 → 날짜별 → blockName별 2단계 그룹핑.
    /// - Parameter ascending: 예정 경기는 오름차순, 완료 경기는 내림차순 정렬
    private func makeGroups(_ matches: [Match], ascending: Bool) -> [DayGroup] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: matches) { cal.startOfDay(for: $0.startTime) }
        let sortedDays = byDay.keys.sorted { ascending ? $0 < $1 : $0 > $1 }
        return sortedDays.map { day in
            let dayMatches = byDay[day]!.sorted { $0.startTime < $1.startTime }
            // 연속된 같은 blockName끼리 묶기 (순서 유지)
            var rawGroups: [(String?, [Match])] = []
            for match in dayMatches {
                if rawGroups.last?.0 == match.blockName {
                    rawGroups[rawGroups.count - 1].1.append(match)
                } else {
                    rawGroups.append((match.blockName, [match]))
                }
            }
            let blockGroups = rawGroups.enumerated().map { i, g in
                BlockGroup(id: "\(day.timeIntervalSince1970)-\(i)", blockName: g.0, matches: g.1)
            }
            return DayGroup(id: "\(day.timeIntervalSince1970)", date: day, blockGroups: blockGroups)
        }
    }

    // MARK: - 목록 모드

    private var scheduleListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                if !viewModel.upcomingMatches.isEmpty {
                    Section {
                        ForEach(makeGroups(viewModel.upcomingMatches, ascending: true)) { dayGroup in
                            dayHeader(dayGroup.date)
                            ForEach(dayGroup.blockGroups) { blockGroup in
                                if let name = blockGroup.blockName {
                                    blockLabel(name)
                                }
                                ForEach(blockGroup.matches) { match in
                                    NavigationLink(value: match) {
                                        MatchCardView(match: match, isLive: false)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16).padding(.vertical, 4)
                                }
                            }
                        }
                    } header: {
                        sectionHeader("예정 경기")
                    }
                }

                if !viewModel.completedMatches.isEmpty {
                    Section {
                        ForEach(makeGroups(viewModel.completedMatches, ascending: false)) { dayGroup in
                            dayHeader(dayGroup.date)
                            ForEach(dayGroup.blockGroups) { blockGroup in
                                if let name = blockGroup.blockName {
                                    blockLabel(name)
                                }
                                ForEach(blockGroup.matches) { match in
                                    NavigationLink(value: match) {
                                        MatchCardView(match: match, isLive: false)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16).padding(.vertical, 4)
                                }
                            }
                        }
                    } header: {
                        sectionHeader("완료 경기")
                    }
                }

                if viewModel.upcomingMatches.isEmpty && viewModel.completedMatches.isEmpty {
                    EmptyStateView("등록된 일정이 없습니다").padding(.top, 60)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        HStack {
            Text(date, style: .date)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
    }

    private func blockLabel(_ name: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3, height: 12)
            Text(name)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 3)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }
}
