//
//  GameWindow.swift
//  LOLIVE
//

import Foundation

// MARK: - Event Detail

struct EventDetailInfo: Codable {
    let strategyCount: Int
    let games: [GameInfo]
    let teamAEsportsId: String  // match.teamA에 대응하는 실제 esports 팀 ID
    let teamBEsportsId: String  // match.teamB에 대응하는 실제 esports 팀 ID
}

struct GameInfo: Identifiable, Codable {
    var id: String { gameId }
    let number: Int
    let gameId: String
    let state: GameInfoState
    let blueTeamId: String
    let redTeamId: String
    let blueBans: [String]
    let redBans: [String]
    let winnerTeamId: String?   // API에서 제공하는 실제 승리 팀 ID (nil이면 미완료 or 데이터 없음)
}

enum GameInfoState: String, Codable {
    case completed
    case inProgress
    case unstarted
    case unneeded

    var isPlayable: Bool {
        self == .completed || self == .inProgress
    }
}

// MARK: - Game Window

struct GameWindow: Identifiable, Codable {
    var id: String { gameId }
    let gameId: String
    let gameState: String
    let blueTeamId: String
    let redTeamId: String
    let bluePlayers: [PlayerStats]
    let redPlayers: [PlayerStats]
    let blueTeamStats: TeamGameStats
    let redTeamStats: TeamGameStats
    let gameTime: Int?   // 인게임 경과 시간 (초), window/details API에서 수신
    let lastFrameTimestamp: Date?   // 최신 프레임 시각 — 라이브 피드가 멈췄는지 판단하는 용도

    enum CodingKeys: String, CodingKey {
        case gameId, gameState, blueTeamId, redTeamId
        case bluePlayers, redPlayers, blueTeamStats, redTeamStats, gameTime, lastFrameTimestamp
    }
}

struct PlayerStats: Identifiable, Hashable, Codable {
    var id: Int { participantId }
    let participantId: Int
    let summonerName: String
    let championId: String
    let role: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let totalGold: Int
    let creepScore: Int
    let level: Int

    enum CodingKeys: String, CodingKey {
        case participantId, summonerName, championId, role
        case kills, deaths, assists, totalGold, creepScore, level
    }
}

struct TeamGameStats: Codable, Hashable {
    let totalGold: Int
    let towers: Int
    let barons: Int
    let totalKills: Int
    let dragons: Int
    let inhibitors: Int
}

extension GameWindow {
    /// 실시간 스트리밍 데이터가 유효한지 여부
    var hasLiveStats: Bool {
        blueTeamStats.totalGold > 0 || blueTeamStats.totalKills > 0
    }
}

extension PlayerStats {
    var hasStats: Bool {
        totalGold > 0 || kills > 0 || deaths > 0 || assists > 0
    }
}

// MARK: - Kill Event

struct KillEvent: Identifiable, Codable {
    let id: UUID
    let gameTimeMs: Int
    let killerParticipantId: Int
    let victimParticipantId: Int
    let assistParticipantIds: [Int]
    let killerTeamId: String

    init(gameTimeMs: Int, killerParticipantId: Int, victimParticipantId: Int,
         assistParticipantIds: [Int] = [], killerTeamId: String = "") {
        self.id = UUID()
        self.gameTimeMs = gameTimeMs
        self.killerParticipantId = killerParticipantId
        self.victimParticipantId = victimParticipantId
        self.assistParticipantIds = assistParticipantIds
        self.killerTeamId = killerTeamId
    }

    var formattedTime: String {
        let s = gameTimeMs / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
