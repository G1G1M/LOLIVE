//
//  LiveStatsService.swift
//  LOLIVE
//

import Foundation

// MARK: - Protocol

protocol LiveStatsServiceProtocol: Sendable {
    func fetchGameWindow(gameId: String, startingTime: Date?) async throws -> GameWindow
    func fetchGameDetails(gameId: String) async throws -> Int?   // 인게임 경과 시간(초) 반환
}

// MARK: - Service

final class LiveStatsService: LiveStatsServiceProtocol {

    private let baseURL = "https://feed.lolesports.com/livestats/v1"

    private let decoder = JSONDecoder()

    func fetchGameWindow(gameId: String, startingTime: Date? = nil) async throws -> GameWindow {
        var components = URLComponents(string: "\(baseURL)/window/\(gameId)")
        if let startingTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            components?.queryItems = [URLQueryItem(name: "startingTime", value: formatter.string(from: startingTime))]
        }
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let windowResponse = try decoder.decode(WindowResponse.self, from: data)
            return map(windowResponse)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    /// Details API: 인게임 경과 시간(초)을 반환합니다.
    /// - 응답 frames의 마지막 프레임에서 gameTime(ms)을 읽어 초로 변환
    /// - window API 프레임에 gameTime이 없을 경우 이 메서드로 대체
    func fetchGameDetails(gameId: String) async throws -> Int? {
        guard let url = URL(string: "\(baseURL)/details/\(gameId)") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let detailsResponse = try? decoder.decode(DetailsResponse.self, from: data)
        guard let gameTimeMs = detailsResponse?.frames.last?.gameTime, gameTimeMs > 0 else {
            return nil
        }
        return gameTimeMs / 1000
    }

    // MARK: - Window DTOs

    private struct WindowResponse: Decodable {
        let esportsGameId: String
        let gameMetadata: WindowGameMetadata
        let frames: [WindowFrame]
    }

    private struct WindowGameMetadata: Decodable {
        let blueTeamMetadata: WindowTeamMetadata
        let redTeamMetadata: WindowTeamMetadata
    }

    private struct WindowTeamMetadata: Decodable {
        let esportsTeamId: String
        let participantMetadata: [WindowParticipantMetadata]
    }

    private struct WindowParticipantMetadata: Decodable {
        let participantId: Int
        let summonerName: String
        let championId: String
        let role: String
    }

    private struct WindowFrame: Decodable {
        let rfc460Timestamp: String
        let gameState: String
        let gameTime: Int?      // 인게임 경과 시간 (ms), API 버전에 따라 존재 여부 다름
        let blueTeam: WindowTeamFrame
        let redTeam: WindowTeamFrame
    }

    private struct WindowTeamFrame: Decodable {
        let totalGold: Int
        let inhibitors: Int
        let towers: Int
        let barons: Int
        let totalKills: Int
        let dragons: [String]
        let participants: [WindowParticipantFrame]
    }

    private struct WindowParticipantFrame: Decodable {
        let participantId: Int
        let totalGold: Int
        let level: Int
        let kills: Int
        let deaths: Int
        let assists: Int
        let creepScore: Int
    }

    // MARK: - Details DTOs

    private struct DetailsResponse: Decodable {
        let frames: [DetailsFrame]
    }

    private struct DetailsFrame: Decodable {
        let gameTime: Int?   // 인게임 경과 시간 (ms)
    }

    // MARK: - Mapping

    private func map(_ response: WindowResponse) -> GameWindow {
        let meta = response.gameMetadata
        let latestFrame = response.frames.last

        let bluePlayers = buildPlayers(
            metadata: meta.blueTeamMetadata.participantMetadata,
            frames: latestFrame?.blueTeam.participants ?? []
        )
        let redPlayers = buildPlayers(
            metadata: meta.redTeamMetadata.participantMetadata,
            frames: latestFrame?.redTeam.participants ?? []
        )

        // window 프레임에 gameTime이 있으면 초로 변환, 없으면 nil (details API fallback 사용)
        let gameTimeSec = latestFrame?.gameTime.map { $0 / 1000 }

        return GameWindow(
            gameId: response.esportsGameId,
            gameState: latestFrame?.gameState ?? "",
            blueTeamId: meta.blueTeamMetadata.esportsTeamId,
            redTeamId: meta.redTeamMetadata.esportsTeamId,
            bluePlayers: bluePlayers,
            redPlayers: redPlayers,
            blueTeamStats: buildTeamStats(latestFrame?.blueTeam),
            redTeamStats: buildTeamStats(latestFrame?.redTeam),
            gameTime: gameTimeSec
        )
    }

    private func buildPlayers(
        metadata: [WindowParticipantMetadata],
        frames: [WindowParticipantFrame]
    ) -> [PlayerStats] {
        let frameMap = Dictionary(uniqueKeysWithValues: frames.map { ($0.participantId, $0) })
        return metadata.map { meta in
            let frame = frameMap[meta.participantId]
            return PlayerStats(
                participantId: meta.participantId,
                summonerName: meta.summonerName,
                championId: meta.championId,
                role: meta.role,
                kills: frame?.kills ?? 0,
                deaths: frame?.deaths ?? 0,
                assists: frame?.assists ?? 0,
                totalGold: frame?.totalGold ?? 0,
                creepScore: frame?.creepScore ?? 0,
                level: frame?.level ?? 1
            )
        }
    }

    private func buildTeamStats(_ frame: WindowTeamFrame?) -> TeamGameStats {
        TeamGameStats(
            totalGold: frame?.totalGold ?? 0,
            towers: frame?.towers ?? 0,
            barons: frame?.barons ?? 0,
            totalKills: frame?.totalKills ?? 0,
            dragons: frame?.dragons.count ?? 0,
            inhibitors: frame?.inhibitors ?? 0
        )
    }
}
