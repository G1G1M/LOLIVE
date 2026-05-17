//
//  StandingsView.swift
//  LOLIVE
//

import SwiftUI

struct StandingsView: View {
    @State private var viewModel = StandingsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if viewModel.isLoadingLeagues {
                    ProgressView("리그 목록 불러오는 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    standingsContent
                }
            }
            .navigationTitle("순위")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
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
            .padding(.bottom, 16)
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
                .padding(.horizontal, 16).padding(.vertical, 10)
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
            HStack(spacing: 6) {
                CachedAsyncImage(url: URL(string: league.imageURL ?? ""))
                    .frame(width: 18, height: 18)
                Text(league.name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
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

    // MARK: - Standings Table

    private var standingsTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider()
            ForEach(Array(viewModel.standings.enumerated()), id: \.offset) { index, standing in
                NavigationLink {
                    TeamDetailView(
                        team: standing.team,
                        league: viewModel.selectedLeague ?? viewModel.leagues[0],
                        standing: standing
                    )
                } label: {
                    standingRow(standing, index: index)
                }
                .buttonStyle(.plain)

                if standing.id != viewModel.standings.last?.id {
                    Divider().padding(.leading, 60)
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
                .frame(width: 28, alignment: .center)
            Text("팀")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("승")
                .frame(width: 36, alignment: .center)
            Text("패")
                .frame(width: 36, alignment: .center)
            Text("승률")
                .frame(width: 52, alignment: .trailing)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func standingRow(_ standing: Standing, index: Int) -> some View {
        HStack {
            Text("\(standing.rank)")
                .font(.subheadline)
                .fontWeight(standing.rank <= 3 ? .bold : .regular)
                .foregroundStyle(rankColor(standing.rank))
                .frame(width: 28, alignment: .center)

            HStack(spacing: 8) {
                CachedAsyncImage(url: URL(string: standing.team.imageURL ?? ""))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(standing.team.name)
                        .font(.subheadline).fontWeight(.medium)
                        .lineLimit(1)
                    Text(standing.team.code)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(standing.wins)")
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 36, alignment: .center)

            Text("\(standing.losses)")
                .font(.subheadline)
                .foregroundStyle(.red)
                .frame(width: 36, alignment: .center)

            Text(String(format: "%.0f%%", standing.winRate * 100))
                .font(.subheadline).fontWeight(.medium)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.secondary)
            Text("순위 데이터를 불러올 수 없습니다")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return Color(.systemGray)
        case 3: return .orange
        default: return .primary
        }
    }
}

#Preview {
    StandingsView()
        .preferredColorScheme(.dark)
}
