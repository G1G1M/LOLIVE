//
//  OracleElixirService+Players.swift
//  LOLIVE
//
//  선수 단위 조회 — 프로필 사진, 리그 공식 출전 명단, 게임별 챔피언 픽(챔피언풀).
//

import Foundation

extension OracleElixirService {

    // MARK: - 프로필 사진

    private struct PlayerResponse: Decodable {
        let playerPhoto: String?
    }

    /// 선수 프로필 사진 URL 반환. 은퇴/현역 여부와 무관하게 조회 가능(실측 확인).
    func fetchPlayerImageURL(summonerName: String) async -> URL? {
        let cacheKey = CacheKey.oracleElixirPlayerImage(summonerName: summonerName)
        if let cached: String = AppDiskCache.get(cacheKey) {
            return cached.isEmpty ? nil : URL(string: cached)
        }

        guard let encoded = Self.pathEscaped(summonerName) else { return nil }

        guard let player: PlayerResponse = await fetch("/players/\(encoded)"),
              let photo = player.playerPhoto, !photo.isEmpty
        else {
            // 결과 없음도 캐싱해 불필요한 재요청 방지 (Leaguepedia 서비스와 동일한 패턴)
            AppDiskCache.set(cacheKey, value: "")
            return nil
        }

        let urlString = "\(cdnBase)/players/\(photo)"
        AppDiskCache.set(cacheKey, value: urlString)
        return URL(string: urlString)
    }

    // MARK: - 리그 공식 출전 선수 명단

    private struct TournamentPlayerRow: Decodable {
        let Player: String
    }

    /// Riot API 팀 로스터(조직 전체 인원 포함)를 "이번 시즌 실제 출전 선수"로 걸러낼 때 쓰는
    /// 기준 명단. 예전엔 Leaguepedia TournamentPlayers 테이블을 썼는데, 레이트리밋이 잦아서
    /// 리그당 요청 1번으로 끝나는 이 엔드포인트로 교체했다.
    func fetchOfficialPlayerNames(league: League) async -> Set<String>? {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return nil }
        guard let tournamentId = await currentTournamentId(oeLeagueName: oeLeagueName) else { return nil }

        // 응답 원본이 아니라 소문자로 정규화한 이름 배열을 캐싱하므로 cachedFetch를 쓰지 않는다.
        let namesCacheKey = CacheKey.oeTournamentPlayers(tournamentId: tournamentId)
        if let cached: [String] = AppDiskCache.get(namesCacheKey) {
            return Set(cached)
        }

        guard let encoded = Self.queryEscaped(tournamentId),
              let rows: [TournamentPlayerRow] = await fetch("/stats/players/byTournament?tournament=\(encoded)")
        else { return nil }

        let names = Set(rows.map { $0.Player.lowercased() })
        guard !names.isEmpty else { return nil }
        AppDiskCache.set(namesCacheKey, value: Array(names))
        return names
    }

    // MARK: - 게임별 챔피언 픽 (챔피언풀)

    /// `/players/gameDetails/{player}` 원본 행 — 필요한 필드만 디코드.
    private struct GameDetailRow: Codable {
        let playerChampion: String
        let kills: Int
        let deaths: Int
        let assists: Int
        let result: Int
        let gameCreation: String
        let tournament: String
    }

    /// 선수의 게임별 챔피언 픽 기록(챔피언풀 탭). Leaguepedia의 ScoreboardPlayers+ScoreboardGames
    /// JOIN을 대체 — 이 엔드포인트는 리그 스코프 없이 선수의 최근 게임을 통째로 주므로(실측:
    /// 50건) 다른 리그/국제전 게임이 섞이지 않도록 `tournament` 표시명이 리그 라벨로 시작하는
    /// 것만 남긴다(실측: "LCK 2026 Rounds 3-4"처럼 짧은 리그 라벨로 시작). 필터링 결과가 0건이면
    /// (라벨 표기가 예상과 다른 리그) 안전하게 원본 전체로 폴백한다.
    func fetchPlayerGameDetails(player: Player, league: League) async -> [ChampionPickEntry]? {
        guard let encoded = Self.pathEscaped(player.summonerName) else { return nil }

        guard let rows: [GameDetailRow] = await cachedFetch(
            .oePlayerGameDetails(summonerName: player.summonerName.lowercased()),
            path: "/players/gameDetails/\(encoded)"
        ), !rows.isEmpty else { return nil }

        let leaguePrefix = league.slug.lowercased()
        let filtered = rows.filter { $0.tournament.lowercased().hasPrefix(leaguePrefix) }
        let scoped = filtered.isEmpty ? rows : filtered

        return scoped.map { row in
            ChampionPickEntry(
                champion: row.playerChampion,
                kills: row.kills, deaths: row.deaths, assists: row.assists,
                won: row.result == 1,
                date: Self.oeDateFmt.date(from: row.gameCreation)
            )
        }
    }
}
