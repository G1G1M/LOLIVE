//
//  TeamSearchView.swift
//  LOLIVE
//

import SwiftUI
import SwiftData

struct TeamSearchView: View {
    @Query private var favoriteTeams: [FavoriteTeam]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = TeamSearchViewModel()
    @State private var searchText = ""

    var filtered: [TeamSearchViewModel.TeamResult] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return viewModel.allTeams }
        return viewModel.allTeams.filter {
            $0.team.name.localizedCaseInsensitiveContains(q) ||
            $0.team.code.localizedCaseInsensitiveContains(q) ||
            $0.league.name.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView("팀 목록 불러오는 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { result in
                        teamRow(result)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "팀 이름 또는 리그 검색")
                }
            }
            .navigationTitle("팀 검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Row

    private func teamRow(_ result: TeamSearchViewModel.TeamResult) -> some View {
        let isFav = favoriteTeams.contains { $0.teamId == result.team.id }
        return HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: result.team.imageURL ?? ""))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.team.name)
                    .font(.subheadline).fontWeight(.semibold)
                Text(result.league.name)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                toggleFavorite(result, isFav: isFav)
            } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isFav ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func toggleFavorite(_ result: TeamSearchViewModel.TeamResult, isFav: Bool) {
        if isFav {
            if let existing = favoriteTeams.first(where: { $0.teamId == result.team.id }) {
                modelContext.delete(existing)
            }
        } else {
            modelContext.insert(FavoriteTeam(team: result.team, league: result.league))
        }
    }
}

#Preview {
    TeamSearchView()
        .preferredColorScheme(.dark)
}
