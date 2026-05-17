//
//  GameWindow.swift
//  LOLIVE
//

import Foundation

// MARK: - Event Detail

struct EventDetailInfo {
    let strategyCount: Int
    let games: [GameInfo]
}

struct GameInfo: Identifiable {
    var id: String { gameId }
    let number: Int
    let gameId: String
    let state: GameInfoState
    let blueTeamId: String
    let redTeamId: String
}

enum GameInfoState: String {
    case completed
    case inProgress
    case unstarted
    case unneeded

    var isPlayable: Bool {
        self == .completed || self == .inProgress
    }
}

// MARK: - Game Window

struct GameWindow: Identifiable {
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
}

struct PlayerStats: Identifiable, Hashable {
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
}

struct TeamGameStats {
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
