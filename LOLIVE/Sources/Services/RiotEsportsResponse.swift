//
//  RiotEsportsResponse.swift
//  LOLIVE
//

import Foundation

// MARK: - Leagues

struct LeaguesResponse: Decodable {
    struct DataWrapper: Decodable {
        let leagues: [LeagueDTO]
    }
    let data: DataWrapper
}

struct LeagueDTO: Decodable {
    let id: String
    let slug: String?   // API 버전에 따라 없을 수 있으므로 optional
    let name: String
    let region: String
    let image: String?
}

// MARK: - Schedule

struct ScheduleResponse: Decodable {
    struct DataWrapper: Decodable {
        let schedule: ScheduleDTO
    }
    let data: DataWrapper
}

struct ScheduleDTO: Decodable {
    let pages: PagesDTO?
    let events: [EventDTO]
}

struct PagesDTO: Decodable {
    let older: String?
    let newer: String?
}

// MARK: - Live

struct LiveResponse: Decodable {
    struct DataWrapper: Decodable {
        let schedule: LiveScheduleDTO
    }
    let data: DataWrapper
}

struct LiveScheduleDTO: Decodable {
    let events: [EventDTO]
}

// MARK: - Event

struct EventDTO: Decodable {
    let startTime: Date
    let state: String
    let blockName: String?   // "Week 1", "Playoffs", "Road to MSI" 등
    let league: EventLeagueDTO
    let match: MatchDTO?
}

struct EventLeagueDTO: Decodable {
    let id: String?   // getLive에는 있음, getSchedule에는 없음
    let name: String
    let slug: String
}

// MARK: - Match

struct MatchDTO: Decodable {
    let id: String
    let teams: [TeamDTO]
    let games: [GameDTO]?
}

struct TeamDTO: Decodable {
    let id: String?   // getLive에는 있음, getSchedule에는 없음
    let name: String
    let code: String
    let image: String?
    let result: ResultDTO?
}

struct ResultDTO: Decodable {
    let outcome: String?
    let gameWins: Int
}

struct GameDTO: Decodable {
    let number: Int
    let state: String
}

// MARK: - Event Details

struct EventDetailsResponse: Decodable {
    struct DataWrapper: Decodable {
        let event: EventDetailDTO
    }
    let data: DataWrapper
}

struct EventDetailDTO: Decodable {
    let id: String
    let match: MatchDetailDTO
}

struct MatchDetailDTO: Decodable {
    let strategy: StrategyDTO
    let teams: [TeamDetailDTO]
    let games: [GameDetailDTO]
}

struct StrategyDTO: Decodable {
    let count: Int
}

struct TeamDetailDTO: Decodable {
    let id: String
}

struct GameDetailDTO: Decodable {
    let number: Int
    let id: String
    let state: String
    let teams: [GameTeamSideDTO]
}

struct GameTeamSideDTO: Decodable {
    let id: String
    let side: String
    let bans: [BanDTO]?
}

struct BanDTO: Decodable {
    let championId: String
}

// MARK: - Tournaments

struct TournamentsResponse: Decodable {
    struct DataWrapper: Decodable {
        let leagues: [TournamentLeagueDTO]
    }
    let data: DataWrapper
}

struct TournamentLeagueDTO: Decodable {
    let tournaments: [TournamentDTO]
}

struct TournamentDTO: Decodable {
    let id: String
    let slug: String
    let startDate: String
    let endDate: String
}

// MARK: - Standings

struct StandingsResponse: Decodable {
    struct DataWrapper: Decodable {
        let standings: [StandingGroupDTO]
    }
    let data: DataWrapper
}

struct StandingGroupDTO: Decodable {
    let stages: [StageDTO]
}

struct StageDTO: Decodable {
    let type: String?   // "groups" (정규시즌), "bracket" (플레이오프)
    let sections: [SectionDTO]
}

struct SectionDTO: Decodable {
    let name: String?
    let rankings: [RankingDTO]
}

struct RankingDTO: Decodable {
    let ordinal: Int
    let teams: [StandingTeamDTO]
}

struct StandingTeamDTO: Decodable {
    let id: String
    let name: String
    let code: String
    let image: String?
    let record: RecordDTO
}

struct RecordDTO: Decodable {
    let wins: Int
    let losses: Int
}

// MARK: - Teams / Roster

struct TeamsResponse: Decodable {
    struct DataWrapper: Decodable {
        let teams: [TeamRosterDTO]
    }
    let data: DataWrapper
}

struct TeamRosterDTO: Decodable {
    let id: String
    let name: String
    let code: String
    let image: String?
    let players: [PlayerDTO]?
}

struct PlayerDTO: Decodable {
    let id: String
    let summonerName: String
    let firstName: String?
    let lastName: String?
    let image: String?
    let role: String?
}
