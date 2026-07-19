//
//  LeaguesView.swift
//  LOLIVE
//

import SwiftUI

struct LeaguesView: View {

    @State private var leagues: [League] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var searchText = ""

    private let service = RiotEsportsService()

    private var filtered: [League] {
        searchText.isEmpty ? leagues : leagues.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let internationalSlugs: Set<String> = ["worlds", "msi"]

    private var grouped: [(region: String, leagues: [League])] {
        let dict = Dictionary(grouping: filtered) { $0.region.isEmpty ? "기타" : $0.region }
        return dict
            .sorted { regionOrder($0.key) < regionOrder($1.key) }
            .compactMap { key, leagues in
                var list = leagues.sorted { $0.name < $1.name }
                if key == "국제 대회" {
                    list = list.filter { internationalSlugs.contains($0.slug) }
                }
                guard !list.isEmpty else { return nil }
                return (region: regionDisplay(key), leagues: list)
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 고정 타이틀 헤더
                HStack {
                    Text("리그")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))

                // 검색 바
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("리그 검색", text: $searchText)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()

                    if isLoading && leagues.isEmpty {
                        LoadingView()
                    } else if loadFailed && leagues.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36)).foregroundStyle(.secondary)
                            Text("데이터를 불러올 수 없습니다")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("다시 시도") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        leagueList
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: League.self) { league in
                if internationalSlugs.contains(league.slug) {
                    TournamentDetailView(league: league)
                } else {
                    LeagueDetailView(league: league)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - List

    private var leagueList: some View {
        List {
            ForEach(grouped, id: \.region) { group in
                Section {
                    ForEach(group.leagues) { league in
                        NavigationLink(value: league) {
                            leagueRow(league, isInternational: group.region == "국제 대회")
                        }
                    }
                } header: {
                    if group.region == "국제 대회" {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.0))
                            Text(group.region)
                                .textCase(nil)
                        }
                    } else {
                        Text(group.region)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func leagueRow(_ league: League, isInternational: Bool = false) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: league.imageURL ?? ""))
                .frame(width: 32, height: 32)

            Text(league.name)
                .font(.subheadline)
                .fontWeight(isInternational ? .semibold : .medium)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data

    private func load() async {
        let hadCache: Bool
        if let cached: [League] = AppDiskCache.get(key: "leagues", maxAge: 24 * 3600), !cached.isEmpty {
            leagues = cached
            hadCache = true
        } else {
            isLoading = true
            hadCache = false
        }
        loadFailed = false
        let result = try? await service.fetchLeagues()
        if let result {
            leagues = result
        } else if !hadCache {
            loadFailed = true
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func regionOrder(_ region: String) -> Int {
        switch region {
        case "국제 대회":                return 0
        case "한국":                     return 1
        case "중국":                     return 2
        case "EMEA":                     return 3
        case "북미":                     return 4
        case "퍼시픽":                   return 5
        case "아메리카스":               return 6
        case "일본":                     return 7
        case "베트남":                   return 8
        case "브라질":                   return 9
        case "홍콩, 마카오, 대만":       return 10
        case "라틴 아메리카":            return 11
        case "라틴 아메리카 북부":       return 12
        case "라틴 아메리카 남부":       return 13
        case "오세아니아":               return 14
        case "독립 국가 연합 (CIS)":     return 15
        default:                         return 16
        }
    }

    private func regionDisplay(_ region: String) -> String {
        return region
    }
}

#Preview {
    LeaguesView()
        .preferredColorScheme(.dark)
}
