//
//  LiveStatsService.swift
//  LOLIVE
//

import Foundation

// MARK: - Protocol

protocol LiveStatsServiceProtocol: Sendable {
    func fetchGameWindow(gameId: String, startingTime: Date?) async throws -> GameWindow
    /// 선수별 빌드·기여도·전투 스탯 (`+Detail` 참고). 화면에서 필요할 때만 부른다.
    func fetchPlayerDetails(gameId: String, startingTime: Date?) async throws -> GameLiveDetail
    func fetchGameDetails(gameId: String) async throws -> Int?   // 인게임 경과 시간(초) 반환
    func fetchKillTimeline(gameId: String) async throws -> [KillEvent]
}

// MARK: - Service

final class LiveStatsService: LiveStatsServiceProtocol {

    private let baseURL = "https://feed.lolesports.com/livestats/v1"
    /// `+Detail` extension 이 같은 호스트를 쓴다.
    var detailBaseURL: String { baseURL }

    private let decoder = JSONDecoder()

    /// 피드가 쓰는 타임스탬프 형식(소수점 초 포함). 요청/응답 양쪽에 같은 걸 쓴다.
    static let feedTimestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `startingTime`은 **10초 경계로 정렬돼 있어야 한다** — 아니면 피드가 무조건 400을 준다(실측).
    /// 응답 프레임의 `rfc460Timestamp`(예: `16:30:09.879Z`)를 그대로 되돌려 보내면 거절당하므로,
    /// 그 시각을 다시 요청에 쓰려면 반드시 이 함수를 거칠 것.
    /// 피드가 내주는 가장 최신 시점. "지금"보다 약 3분 25초 이내를 요청하면 400이라
    /// (스포일러 방지로 보인다) 여유를 두고 4분 전을 쓴다.
    static func liveEdge(now: Date = Date()) -> Date {
        alignedToTenSeconds(now.addingTimeInterval(-240))
    }

    static func alignedToTenSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 10).rounded(.down) * 10)
    }

    func fetchGameWindow(gameId: String, startingTime: Date? = nil) async throws -> GameWindow {
        var components = URLComponents(string: "\(baseURL)/window/\(gameId)")
        if let startingTime {
            components?.queryItems = [
                URLQueryItem(name: "startingTime",
                             value: Self.feedTimestamp.string(from: Self.alignedToTenSeconds(startingTime)))
            ]
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

        return try decodeWindow(data)
    }

    /// 네트워크와 분리된 디코딩 — 실측 응답 픽스처로 테스트에서 직접 호출한다.
    /// (Riot이 필드를 조용히 빼도 테스트가 먼저 알아채게 하려는 목적)
    func decodeWindow(_ data: Data) throws -> GameWindow {
        do {
            return map(try decoder.decode(WindowResponse.self, from: data))
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

    func fetchKillTimeline(gameId: String) async throws -> [KillEvent] {
        guard let url = URL(string: "\(baseURL)/details/\(gameId)") else { return [] }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else { return [] }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frames = json["frames"] as? [[String: Any]] else { return [] }

        var events: [KillEvent] = []
        for frame in frames {
            let frameEvents = (frame["events"] as? [[String: Any]]) ?? []
            for event in frameEvents {
                let type = (event["EventType"] as? String
                    ?? event["eventType"] as? String ?? "").lowercased()
                guard type.contains("kill") else { continue }

                let ts = event["Timestamp"] as? Int ?? event["timestamp"] as? Int
                let killerId = event["KillerParticipantID"] as? Int
                    ?? event["killerParticipantId"] as? Int
                let victimId = event["VictimParticipantID"] as? Int
                    ?? event["victimParticipantId"] as? Int
                let assists = event["AssistingParticipantIDs"] as? [Int]
                    ?? event["assistingParticipantIds"] as? [Int] ?? []
                let killerTeam = event["KillerTeamID"] as? String
                    ?? event["killerTeamId"] as? String ?? ""

                guard let ts, let killerId, let victimId else { continue }
                events.append(KillEvent(
                    gameTimeMs: ts,
                    killerParticipantId: killerId,
                    victimParticipantId: victimId,
                    assistParticipantIds: assists,
                    killerTeamId: killerTeam
                ))
            }
        }
        return events.sorted { $0.gameTimeMs < $1.gameTimeMs }
    }

    // MARK: - Window DTOs

    private struct WindowResponse: Decodable {
        let esportsGameId: String
        let gameMetadata: WindowGameMetadata
        let frames: [WindowFrame]
    }

    private struct WindowGameMetadata: Decodable {
        /// 그 경기가 돌아간 패치(예: "16.16.809.3269"). 시즌이 바뀌면 스탯 해석이 달라져서
        /// 과거 경기를 볼 때 기준이 된다.
        let patchVersion: String?
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
        let currentHealth: Int?
        let maxHealth: Int?
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
        let lastFrameTimestamp = latestFrame.flatMap { Self.feedTimestamp.date(from: $0.rfc460Timestamp) }

        return GameWindow(
            gameId: response.esportsGameId,
            gameState: latestFrame?.gameState ?? "",
            blueTeamId: meta.blueTeamMetadata.esportsTeamId,
            redTeamId: meta.redTeamMetadata.esportsTeamId,
            bluePlayers: bluePlayers,
            redPlayers: redPlayers,
            blueTeamStats: buildTeamStats(latestFrame?.blueTeam),
            redTeamStats: buildTeamStats(latestFrame?.redTeam),
            gameTime: gameTimeSec,
            lastFrameTimestamp: lastFrameTimestamp,
            patchVersion: meta.patchVersion
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
                level: frame?.level ?? 1,
                currentHealth: frame?.currentHealth,
                maxHealth: frame?.maxHealth
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
            inhibitors: frame?.inhibitors ?? 0,
            dragonTypes: frame?.dragons
        )
    }
}
