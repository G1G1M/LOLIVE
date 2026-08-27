//
//  FavoriteTeamProvider.swift
//  LOLIVEWidgets
//
//  위젯 타임라인 데이터 조회 로직 — 뷰와 무관해 FavoriteTeamWidget.swift에서 분리.
//

import WidgetKit

// MARK: - Team Row Info (Large 위젯용)

struct TeamRowInfo: Sendable {
    let teamCode: String
    let teamName: String
    let leagueName: String
    let teamImageData: Data?
    let nextMatch: WidgetNetworkService.NextMatchInfo?
    let opponentImageData: Data?
}

// MARK: - Entry

struct FavoriteTeamEntry: TimelineEntry {
    let date: Date
    // 현재 선택 팀 (Small / Medium)
    let teamId: String
    let teamName: String
    let teamCode: String
    let teamImageData: Data?
    let leagueName: String
    let nextMatch: WidgetNetworkService.NextMatchInfo?
    let opponentImageData: Data?
    let currentIndex: Int
    let totalTeams: Int
    let isConfigured: Bool
    // 전체 팀 목록 (Large)
    let allTeams: [TeamRowInfo]

    static let placeholder: FavoriteTeamEntry = {
        let sampleMatch = WidgetNetworkService.NextMatchInfo(
            opponentName: "Gen.G",
            opponentCode: "GEN",
            opponentImageURL: nil,
            startTime: .now.addingTimeInterval(1800),
            isLive: false
        )
        let row1 = TeamRowInfo(teamCode: "T1",  teamName: "T1",    leagueName: "LCK", teamImageData: nil, nextMatch: sampleMatch, opponentImageData: nil)
        let row2 = TeamRowInfo(teamCode: "GEN", teamName: "Gen.G", leagueName: "LCK", teamImageData: nil, nextMatch: nil,         opponentImageData: nil)
        let row3 = TeamRowInfo(teamCode: "DRX", teamName: "DRX",   leagueName: "LCK", teamImageData: nil, nextMatch: nil,         opponentImageData: nil)
        return FavoriteTeamEntry(
            date: .now, teamId: "t1", teamName: "T1", teamCode: "T1",
            teamImageData: nil, leagueName: "LCK", nextMatch: sampleMatch,
            opponentImageData: nil, currentIndex: 0, totalTeams: 3, isConfigured: true,
            allTeams: [row1, row2, row3]
        )
    }()
}

// MARK: - Provider

struct FavoriteTeamProvider: TimelineProvider {

    /// 경기 시작 몇 초 전부터 라이브 API 확인을 시작할지 — 예정 시각보다 일찍 시작하는 경기 감지용
    private static let earlyLiveCheckWindow: TimeInterval = 90 * 60

    func placeholder(in context: Context) -> FavoriteTeamEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (FavoriteTeamEntry) -> Void) {
        Task { completion(await buildEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoriteTeamEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            let nextUpdate: Date
            if let match = entry.nextMatch {
                if match.isLive {
                    // 라이브 중: 15분마다 종료 감지
                    nextUpdate = .now.addingTimeInterval(900)
                } else {
                    let timeToMatch = match.startTime.timeIntervalSinceNow
                    if timeToMatch > Self.earlyLiveCheckWindow {
                        // 예정 1.5시간 이상 전: 라이브 체크 시작 시점에 갱신
                        nextUpdate = match.startTime.addingTimeInterval(-Self.earlyLiveCheckWindow)
                    } else {
                        // 1.5시간 이내 또는 이미 지남: 5분마다 (일찍 시작 즉시 감지)
                        nextUpdate = .now.addingTimeInterval(300)
                    }
                }
            } else {
                nextUpdate = .now.addingTimeInterval(3600)
            }
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    // MARK: - Private

    private func buildEntry() async -> FavoriteTeamEntry {
        let teams = SharedDataService.loadFavoriteTeams()
        guard !teams.isEmpty else {
            return FavoriteTeamEntry(
                date: .now, teamId: "", teamName: "", teamCode: "",
                teamImageData: nil, leagueName: "", nextMatch: nil,
                opponentImageData: nil, currentIndex: 0, totalTeams: 0, isConfigured: false,
                allTeams: []
            )
        }

        var idx = SharedDataService.loadCurrentTeamIndex()
        idx = max(0, min(idx, teams.count - 1))
        let fav = teams[idx]

        // 전체 팀의 sharedMatch를 미리 로드 (Large 위젯과 공유)
        let allSharedMatches: [String: SharedNextMatch] = Dictionary(
            uniqueKeysWithValues: teams.compactMap { t -> (String, SharedNextMatch)? in
                guard let m = SharedDataService.loadNextMatch(teamCode: t.teamCode) else { return nil }
                return (t.teamCode.uppercased(), m)
            }
        )
        let currentSharedMatch = allSharedMatches[fav.teamCode.uppercased()]

        // sharedMatch 없는 팀이 있거나, 예정 1.5시간 이내인 팀이 있으면 라이브 API 1회 호출
        let noSharedData = teams.contains { allSharedMatches[$0.teamCode.uppercased()] == nil }
        let needsLiveCheck = noSharedData || allSharedMatches.values.contains {
            !$0.isLive && $0.startTime.timeIntervalSinceNow < Self.earlyLiveCheckWindow
        }

        async let liveInfoTask = WidgetNetworkService.fetchAllLiveMatchInfo(onlyIf: needsLiveCheck)
        async let apiMatchTask: WidgetNetworkService.NextMatchInfo? = currentSharedMatch == nil
            ? WidgetNetworkService.fetchNextMatch(leagueId: fav.leagueId, teamCode: fav.teamCode)
            : nil
        async let teamImgTask = fetchImageData(fav.teamImageURL)
        let (liveInfo, apiMatch, teamImg) = await (liveInfoTask, apiMatchTask, teamImgTask)

        // 우선순위: 라이브 API 확인 > App Group 데이터 > 스케줄 API fallback
        // sharedMatch 없을 때도 liveInfo 활용 (MSI 등 홈 리그 외 경기 커버)
        let shouldCheckLive = currentSharedMatch == nil || (currentSharedMatch.map {
            !$0.isLive && $0.startTime.timeIntervalSinceNow < Self.earlyLiveCheckWindow
        } ?? false)
        let liveCheck = shouldCheckLive
            ? liveInfo[WidgetNetworkService.liveInfoKey(code: fav.teamCode, leagueId: fav.leagueId)]
            : nil
        let match = liveCheck ?? currentSharedMatch.map {
            WidgetNetworkService.NextMatchInfo(
                opponentName: $0.opponentName,
                opponentCode: $0.opponentCode,
                opponentImageURL: $0.opponentImageURL,
                startTime: $0.startTime,
                isLive: $0.isLive,
                myScore: $0.myScore,
                oppScore: $0.oppScore,
                currentGame: $0.currentGame
            )
        } ?? apiMatch

        let oppImg = await fetchImageData(match?.opponentImageURL)

        let allTeamsData = await loadAllTeams(teams, liveInfo: liveInfo, sharedMatches: allSharedMatches)
        let leagueName = currentSharedMatch?.leagueName ?? fav.leagueName

        return FavoriteTeamEntry(
            date: .now,
            teamId: fav.teamId,
            teamName: fav.teamName,
            teamCode: fav.teamCode,
            teamImageData: teamImg,
            leagueName: leagueName,
            nextMatch: match,
            opponentImageData: oppImg,
            currentIndex: idx,
            totalTeams: teams.count,
            isConfigured: true,
            allTeams: allTeamsData
        )
    }

    private func loadAllTeams(
        _ teams: [SharedFavoriteTeam],
        liveInfo: [String: WidgetNetworkService.NextMatchInfo],
        sharedMatches: [String: SharedNextMatch]
    ) async -> [TeamRowInfo] {
        await withTaskGroup(of: (Int, TeamRowInfo).self) { group in
            for (i, fav) in teams.enumerated() {
                let sharedMatch = sharedMatches[fav.teamCode.uppercased()]
                let shouldCheckLive = sharedMatch == nil || (sharedMatch.map {
                    !$0.isLive && $0.startTime.timeIntervalSinceNow < Self.earlyLiveCheckWindow
                } ?? false)
                let liveCheck = shouldCheckLive
                    ? liveInfo[WidgetNetworkService.liveInfoKey(code: fav.teamCode, leagueId: fav.leagueId)]
                    : nil

                group.addTask {
                    async let apiMatchTask: WidgetNetworkService.NextMatchInfo? = (sharedMatch == nil)
                        ? WidgetNetworkService.fetchNextMatch(leagueId: fav.leagueId, teamCode: fav.teamCode)
                        : nil
                    async let img = fetchImageData(fav.teamImageURL)
                    let (apiMatch, teamImg) = await (apiMatchTask, img)

                    let match = liveCheck ?? sharedMatch.map {
                        WidgetNetworkService.NextMatchInfo(
                            opponentName: $0.opponentName,
                            opponentCode: $0.opponentCode,
                            opponentImageURL: $0.opponentImageURL,
                            startTime: $0.startTime,
                            isLive: $0.isLive,
                            myScore: $0.myScore,
                            oppScore: $0.oppScore,
                            currentGame: $0.currentGame
                        )
                    } ?? apiMatch

                    let oppImg = await fetchImageData(match?.opponentImageURL)
                    let leagueName = sharedMatch?.leagueName ?? fav.leagueName
                    return (i, TeamRowInfo(
                        teamCode: fav.teamCode,
                        teamName: fav.teamName,
                        leagueName: leagueName,
                        teamImageData: teamImg,
                        nextMatch: match,
                        opponentImageData: oppImg
                    ))
                }
            }
            var results: [(Int, TeamRowInfo)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private func fetchImageData(_ urlString: String?) async -> Data? {
        guard let str = urlString, let url = URL(string: str) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}
