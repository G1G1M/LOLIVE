//
//  FirebaseEsportsService.swift
//  LOLIVE
//
//  Firebase Firestore를 통해 경기 데이터를 읽는 서비스.
//  fetchLeagues / fetchSchedule / fetchLive → Firestore (서버 캐시, 빠름)
//  fetchEventDetails / fetchTournaments / fetchStandings / fetchTeamRoster → Riot API 직접 (변경 드묾)
//

import Foundation
import FirebaseFirestore

final class FirebaseEsportsService: RiotEsportsServiceProtocol {

    static let shared = FirebaseEsportsService()

    private let db   = Firestore.firestore()
    private let riot = RiotEsportsService()   // 직접 API 폴백용

    private init() {}

    // MARK: - fetchLeagues

    func fetchLeagues() async throws -> [League] {
        if let cached: [League] = AppDiskCache.get(key: "fb_leagues", maxAge: 30 * 60) {
            return cached
        }
        let snap = try await db.collection("leagues").getDocuments()
        let leagues = snap.documents.compactMap { League(firestoreData: $0.data()) }
        if !leagues.isEmpty { AppDiskCache.set(key: "fb_leagues", value: leagues) }
        return leagues
    }

    // MARK: - fetchSchedule

    func fetchSchedule(league: League) async throws -> [Match] {
        let key = "fb_schedule_\(league.id)"
        if let cached: [Match] = AppDiskCache.get(key: key, maxAge: 5 * 60) { return cached }

        let fiveDaysAgo = Date().addingTimeInterval(-5 * 86_400)
        let snap = try await db.collection("matches")
            .whereField("league.id", isEqualTo: league.id)
            .whereField("startTime", isGreaterThan: Timestamp(date: fiveDaysAgo))
            .order(by: "startTime")
            .getDocuments()

        let matches = snap.documents.compactMap { Match(firestoreData: $0.data()) }
        if !matches.isEmpty { AppDiskCache.set(key: key, value: matches) }
        return matches
    }

    // MARK: - fetchAllSchedule

    func fetchAllSchedule(league: League) async throws -> [Match] {
        let key = "fb_all_schedule_\(league.id)"
        if let cached: [Match] = AppDiskCache.get(key: key, maxAge: 2 * 3600) { return cached }

        let snap = try await db.collection("matches")
            .whereField("league.id", isEqualTo: league.id)
            .order(by: "startTime")
            .getDocuments()

        let matches = snap.documents.compactMap { Match(firestoreData: $0.data()) }
        if !matches.isEmpty { AppDiskCache.set(key: key, value: matches) }
        return matches
    }

    // MARK: - fetchLive

    func fetchLive() async throws -> [LiveMatch] {
        let snap = try await db.collection("liveMatches").getDocuments()
        return snap.documents.compactMap { doc -> LiveMatch? in
            let data = doc.data()
            guard let matchData = data["match"] as? [String: Any],
                  let match = Match(firestoreData: matchData) else { return nil }
            let currentSet = data["currentSet"] as? Int ?? 1
            return LiveMatch(match: match, currentSet: currentSet, lastUpdated: Date())
        }
    }

    // MARK: - 직접 API 폴백 (변경이 드문 데이터)

    func fetchEventDetails(matchId: String) async throws -> EventDetailInfo {
        try await riot.fetchEventDetails(matchId: matchId)
    }

    func fetchTournaments(leagueId: String) async throws -> [Tournament] {
        try await riot.fetchTournaments(leagueId: leagueId)
    }

    func fetchStandings(tournamentId: String) async throws -> [Standing] {
        try await riot.fetchStandings(tournamentId: tournamentId)
    }

    func fetchTeamRoster(teamId: String) async throws -> [Player] {
        try await riot.fetchTeamRoster(teamId: teamId)
    }
}

// MARK: - Firestore 디코딩 extensions

private extension League {
    init?(firestoreData data: [String: Any]) {
        guard let id     = data["id"]     as? String,
              let name   = data["name"]   as? String,
              let region = data["region"] as? String
        else { return nil }
        self.init(
            id: id,
            slug: data["slug"] as? String ?? "",
            name: name,
            region: region,
            imageURL: data["imageURL"] as? String
        )
    }
}

private extension Team {
    init?(firestoreData data: [String: Any]) {
        guard let id   = data["id"]   as? String,
              let name = data["name"] as? String,
              let code = data["code"] as? String
        else { return nil }
        self.init(id: id, name: name, code: code, imageURL: data["imageURL"] as? String)
    }
}

private extension Match {
    init?(firestoreData data: [String: Any]) {
        guard let id          = data["id"]       as? String,
              let leagueData  = data["league"]   as? [String: Any],
              let teamAData   = data["teamA"]    as? [String: Any],
              let teamBData   = data["teamB"]    as? [String: Any],
              let stateStr    = data["state"]    as? String,
              let state       = MatchState(rawValue: stateStr),
              let league      = League(firestoreData: leagueData),
              let teamA       = Team(firestoreData: teamAData),
              let teamB       = Team(firestoreData: teamBData)
        else { return nil }

        let startTime: Date
        if let ts = data["startTime"] as? Timestamp {
            startTime = ts.dateValue()
        } else if let str = data["startTime"] as? String {
            startTime = ISO8601DateFormatter().date(from: str) ?? Date()
        } else {
            return nil
        }

        self.init(
            id: id,
            league: league,
            teamA: teamA,
            teamB: teamB,
            scoreA: data["scoreA"] as? Int ?? 0,
            scoreB: data["scoreB"] as? Int ?? 0,
            startTime: startTime,
            state: state,
            blockName: data["blockName"] as? String
        )
    }
}
