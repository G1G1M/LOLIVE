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
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        standingsContent
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
    }

    // MARK: - League Selector

    private var leagueSelector: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.leagues) { league in
                        leagueChip(league)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            Divider()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func leagueChip(_ league: League) -> some View {
        let isSelected = viewModel.selectedLeague?.id == league.id
        return Button {
            Task { await viewModel.selectLeague(league) }
        } label: {
            HStack(spacing: 5) {
                CachedAsyncImage(url: URL(string: league.imageURL ?? ""))
                    .frame(width: 16, height: 16)
                Text(league.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
        }
    }

    // MARK: - Standings Body

    @ViewBuilder
    private var standingsBody: some View {
        if viewModel.isLoadingStandings {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else if viewModel.standings.isEmpty {
            emptyState
        } else {
            standingsTable
        }
    }

    // MARK: - Table

    private var standingsTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider().padding(.horizontal, 16)
            ForEach(Array(viewModel.standings.enumerated()), id: \.offset) { index, standing in
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

                if standing.id != viewModel.standings.last?.id {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(16)
    }

    private var tableHeader: some View {
        HStack {
            Text("#")
                .frame(width: 32, alignment: .center)
                .foregroundStyle(.secondary)
            Text("팀")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
            Text("W")
                .frame(width: 34, alignment: .center)
                .foregroundStyle(.blue)
            Text("L")
                .frame(width: 34, alignment: .center)
                .foregroundStyle(.red)
            Text("Win%")
                .frame(width: 50, alignment: .trailing)
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
                CachedAsyncImage(url: URL(string: standing.team.imageURL ?? ""))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(standing.team.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(standing.team.code)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 승
            Text("\(standing.wins)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 34, alignment: .center)

            // 패
            Text("\(standing.losses)")
                .font(.system(size: 14))
                .foregroundStyle(.red)
                .frame(width: 34, alignment: .center)

            // 승률
            Text(String(format: "%.0f%%", standing.winRate * 100))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(winRateColor(standing.winRate))
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("순위 데이터를 불러올 수 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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

    private func winRateColor(_ rate: Double) -> Color {
        if rate >= 0.6 { return .blue }
        if rate < 0.4  { return .secondary }
        return Color(.label)
    }
}

#Preview {
    StandingsView()
        .preferredColorScheme(.dark)
}
