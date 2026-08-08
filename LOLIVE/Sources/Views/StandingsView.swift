//
//  StandingsView.swift
//  LOLIVE
//

import SwiftUI

struct StandingsView: View {
    @State private var viewModel = StandingsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 고정 타이틀
                HStack {
                    Text("순위")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                    if viewModel.isLoadingLeagues {
                        LoadingView()
                    } else if viewModel.loadFailed {
                        ErrorRetryView { Task { await viewModel.loadLeagues() } }
                    } else {
                        standingsContent
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // Match.self/League.self는 탭 루트에서 한 번씩만 등록(중첩 화면에서 중복 등록하면
            // 뒤로가기 시 화면이 다시 만들어지는 버그가 있었음 — LeagueDetailView.swift 주석 참고).
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
        .task { await viewModel.loadLeagues() }
    }

    // MARK: - Content

    private var standingsContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    standingsBody
                } header: {
                    leagueSelector
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await viewModel.refreshStandings()
        }
    }

    // MARK: - League Selector

    private var leagueSelector: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(viewModel.leagues) { league in
                        Button {
                            Task { await viewModel.selectLeague(league) }
                        } label: {
                            if viewModel.selectedLeague?.id == league.id {
                                Label(league.name, systemImage: "checkmark")
                            } else {
                                Text(league.name)
                            }
                        }
                    }
                } label: {
                    MenuFilterLabel {
                        if let selected = viewModel.selectedLeague {
                            LogoBadgeView(imageURL: selected.imageURL, size: 20)
                            Text(selected.name)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Standings Body

    private var standingsBody: some View {
        Group {
            if viewModel.isLoadingStandings {
                LoadingView("순위 불러오는 중...")
                    .frame(minHeight: 120)
            } else if viewModel.standings.isEmpty {
                EmptyStateView("순위 데이터가 없습니다")
            } else {
                standingsTable
            }
        }
        // 리그 칩을 바꿀 때마다 isLoadingStandings가 토글되는데 애니메이션이 없어 로딩↔순위표가
        // 매번 "툭" 끊기듯 바뀌었음 — 부드러운 크로스페이드로 전환
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoadingStandings)
    }

    // MARK: - Table

    private var standingsTable: some View {
        let groups = viewModel.standingGroups
        return VStack(spacing: groups.isEmpty ? 0 : 12) {
            if groups.isEmpty {
                standingsBlock(standings: viewModel.standings, showGroupHeader: false, groupName: nil)
            } else {
                ForEach(groups, id: \.name) { group in
                    standingsBlock(standings: group.standings, showGroupHeader: true, groupName: group.name)
                }
            }
        }
        .padding(16)
    }

    private func standingsBlock(standings: [Standing], showGroupHeader: Bool, groupName: String?) -> some View {
        VStack(spacing: 0) {
            if showGroupHeader, let name = groupName {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 14)
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                Divider().padding(.horizontal, 16)
            }
            tableHeader
            Divider().padding(.horizontal, 16)
            ForEach(Array(standings.enumerated()), id: \.offset) { _, standing in
                NavigationLink {
                    TeamDetailView(
                        team: standing.team,
                        league: viewModel.selectedLeague ?? viewModel.leagues[0],
                        standing: standing
                    )
                } label: {
                    standingRow(standing)
                }
                .buttonStyle(.plain)
                if standing.id != standings.last?.id {
                    Divider().padding(.leading, 72)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 32, alignment: .center)
                .foregroundStyle(.secondary)
            Text("팀")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Text("W")
                    .foregroundStyle(.blue)
                    .frame(width: 22, alignment: .center)
                Text("-")
                    .foregroundStyle(.secondary)
                    .frame(width: 10, alignment: .center)
                Text("L")
                    .foregroundStyle(.red)
                    .frame(width: 22, alignment: .center)
            }
            .frame(width: 54)
            Text("GD")
                .frame(width: 44, alignment: .center)
                .foregroundStyle(.secondary)
            Text("Win%")
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func standingRow(_ standing: Standing) -> some View {
        HStack(spacing: 0) {
            // 순위
            Text("\(standing.rank)")
                .font(.system(size: 14, weight: standing.rank <= 3 ? .bold : .regular))
                .foregroundStyle(rankColor(standing.rank))
                .frame(width: 32, alignment: .center)

            // 팀 정보
            HStack(spacing: 10) {
                LogoBadgeView(imageURL: standing.team.imageURL, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(standing.team.name)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(standing.team.code)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 승-패
            HStack(spacing: 0) {
                Text("\(standing.wins)")
                    .foregroundStyle(.blue)
                    .monospacedDigit()
                    .frame(width: 22, alignment: .center)
                Text("-")
                    .foregroundStyle(.secondary)
                    .frame(width: 10, alignment: .center)
                Text("\(standing.losses)")
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .frame(width: 22, alignment: .center)
            }
            .font(.system(size: 13, weight: .medium))
            .frame(width: 54)

            // 세트 득실
            Text(gdString(standing.gameDiff))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color(.label))
                .frame(width: 44, alignment: .center)

            // 승률
            Text(String(format: "%.0f%%", standing.winRate * 100))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.label))
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.8, blue: 0.0)   // gold
        case 2: return Color(.systemGray)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)   // bronze
        default: return Color(.label)
        }
    }

    private func gdString(_ gd: Int) -> String {
        if gd > 0 { return "+\(gd)" }
        return "\(gd)"
    }

}

#Preview {
    StandingsView()
        .preferredColorScheme(.dark)
}
