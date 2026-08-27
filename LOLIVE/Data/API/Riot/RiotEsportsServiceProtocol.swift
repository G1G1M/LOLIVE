//
//  RiotEsportsServiceProtocol.swift
//  LOLIVE
//
//  Riot Esports API 연동의 계약(프로토콜)과 공통 에러 타입.
//  ViewModel은 구현체가 아니라 이 프로토콜에 의존해서, 테스트에서 Mock으로 갈아끼울 수 있다.
//

import Foundation

// MARK: - APIError

enum APIError: Error {
    case invalidURL
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
    case unknown(Error)
}

// MARK: - Protocol

protocol RiotEsportsServiceProtocol: Sendable {
    func fetchLeagues() async throws -> [League]
    func fetchSchedule(league: League) async throws -> [Match]
    /// 캐시·Leaguepedia 보정 없이 Riot 원본 일정만 가져온다 — 화면을 우선 즉시 채우고,
    /// 보정된 결과(fetchSchedule)는 백그라운드에서 나중에 반영하는 용도.
    func fetchScheduleRaw(league: League) async throws -> [Match]
    func fetchAllSchedule(league: League) async throws -> [Match]
    func fetchLive() async throws -> [LiveMatch]
    func fetchEventDetails(matchId: String) async throws -> EventDetailInfo
    func fetchTournaments(leagueId: String) async throws -> [Tournament]
    func fetchStandings(tournamentId: String) async throws -> [Standing]
    func fetchTeamRoster(teamId: String) async throws -> [Player]
}
