//
//  OnboardingLoader.swift
//  LOLIVE
//
//  OnboardingView가 보여줄 실제 경기 데이터를 로드하는 로직 — 뷰와 무관해 별도 파일로 분리.
//

import SwiftUI

@Observable
@MainActor
final class OnboardingLoader {
    var match: Match?
    var gameWindow: GameWindow?
    var playerImageURLs: [String: URL] = [:]  // summonerName → 프로필 이미지 URL

    // MARK: - Disk Cache

    private static let cacheFile: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("onboarding_v1.json")
    }()

    private struct CachedData: Codable {
        let matchId: String
        let scoreA: Int
        let scoreB: Int
        let teamAName: String
        let teamACode: String
        let teamAImageURL: String?
        let teamBName: String
        let teamBCode: String
        let teamBImageURL: String?
        let leagueName: String
        let gameId: String?
        let playerImageURLs: [String: String]  // summonerName → URL string
    }

    func load() async {
        // 1. 디스크 캐시 확인
        if let cached = loadCache() {
            restoreFromCache(cached)
            return
        }
        // 2. 신규 fetch (T1 vs Gen.G 우선)
        await fetchAndCache()
    }

    private func loadCache() -> CachedData? {
        guard let data = try? Data(contentsOf: Self.cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else { return nil }
        return cached
    }

    private func restoreFromCache(_ cached: CachedData) {
        let league = League(id: "lck", slug: "lck", name: cached.leagueName, region: "한국", imageURL: nil)
        let teamA = Team(id: cached.teamACode, name: cached.teamAName, code: cached.teamACode, imageURL: cached.teamAImageURL)
        let teamB = Team(id: cached.teamBCode, name: cached.teamBName, code: cached.teamBCode, imageURL: cached.teamBImageURL)
        match = Match(id: cached.matchId, league: league, teamA: teamA, teamB: teamB,
                      scoreA: cached.scoreA, scoreB: cached.scoreB,
                      startTime: Date(), state: .completed)
        playerImageURLs = cached.playerImageURLs.compactMapValues { URL(string: $0) }

        // GameWindow는 GameWindowCache에서 복원
        if let gameId = cached.gameId {
            Task {
                gameWindow = await GameWindowCache.shared.window(for: gameId)
                // 이전 캐시에 이미지 URL이 없으면 재시도
                guard playerImageURLs.isEmpty,
                      let window = gameWindow,
                      let currentMatch = match else { return }
                let oracleElixir = OracleElixirService.shared
                let targets = [window.bluePlayers.first, window.redPlayers.first].compactMap { $0 }
                var urls: [String: URL] = [:]
                for player in targets {
                    if let url = await oracleElixir.fetchPlayerImageURL(summonerName: player.summonerName) {
                        urls[player.summonerName] = url
                    }
                }
                guard !urls.isEmpty else { return }
                playerImageURLs = urls
                saveCache(match: currentMatch, gameId: gameId, playerImageURLs: urls)
            }
        }
    }

    private func saveCache(match: Match, gameId: String?, playerImageURLs: [String: URL]) {
        let data = CachedData(
            matchId: match.id,
            scoreA: match.scoreA, scoreB: match.scoreB,
            teamAName: match.teamA.name, teamACode: match.teamA.code, teamAImageURL: match.teamA.imageURL,
            teamBName: match.teamB.name, teamBCode: match.teamB.code, teamBImageURL: match.teamB.imageURL,
            leagueName: match.league.name,
            gameId: gameId,
            playerImageURLs: playerImageURLs.mapValues { $0.absoluteString }
        )
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: Self.cacheFile, options: .atomic)
        }
    }

    private func fetchAndCache() async {
        let esports = RiotEsportsService()

        guard let leagues = try? await esports.fetchLeagues(),
              let lck = leagues.first(where: { $0.slug == "lck" }) else { return }

        guard let schedule = try? await esports.fetchSchedule(league: lck) else { return }

        // T1 vs Gen.G 완료 경기 우선, 없으면 아무 완료 경기
        let recentMatch = schedule.first(where: {
            $0.state == .completed &&
            Set([$0.teamA.code, $0.teamB.code]) == Set(["T1", "GEN"])
        }) ?? schedule.first(where: { $0.state == .completed })

        guard let recentMatch else { return }
        match = recentMatch

        guard let detail = try? await esports.fetchEventDetails(matchId: recentMatch.id),
              let game = detail.games.first(where: { $0.state == .completed }) else { return }

        let gameWindowCache = GameWindowCache.shared
        if let cached = await gameWindowCache.window(for: game.gameId) {
            gameWindow = cached
        } else {
            let liveStats = LiveStatsService()
            for offset: Double in [75, 60, 45, 30] {
                let startTime = recentMatch.startTime.addingTimeInterval(offset * 60)
                if let w = try? await liveStats.fetchGameWindow(gameId: game.gameId, startingTime: startTime),
                   w.hasLiveStats {
                    gameWindow = w
                    await gameWindowCache.save(w)
                    break
                }
            }
        }

        // 선수 프로필 이미지 (summonerName 키로 저장)
        guard let window = gameWindow else {
            saveCache(match: recentMatch, gameId: game.gameId, playerImageURLs: [:])
            return
        }
        let targets = [window.bluePlayers.first, window.redPlayers.first].compactMap { $0 }
        let oracleElixir = OracleElixirService.shared
        var urls: [String: URL] = [:]
        for player in targets {
            guard !Task.isCancelled else { break }
            if let url = await oracleElixir.fetchPlayerImageURL(summonerName: player.summonerName) {
                urls[player.summonerName] = url
            }
        }
        playerImageURLs = urls
        saveCache(match: recentMatch, gameId: game.gameId, playerImageURLs: urls)
    }
}
