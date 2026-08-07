//
//  Match.swift
//  LOLIVE
//

import Foundation

enum MatchState: String, Codable, Hashable {
    case unstarted
    case inProgress
    case completed
}

struct Match: Codable, Identifiable, Hashable {
    let id: String
    let league: League
    let teamA: Team
    let teamB: Team
    let scoreA: Int
    let scoreB: Int
    let startTime: Date
    let state: MatchState
    let blockName: String?  // "Week 1", "Playoffs", "Road to MSI" 등
    let games: [BackfilledGameDetail]?  // 과거 시즌 백필 경기에만 존재(oe.datalisk.io 게임별 상세)

    init(id: String, league: League, teamA: Team, teamB: Team,
         scoreA: Int, scoreB: Int, startTime: Date, state: MatchState,
         blockName: String? = nil, games: [BackfilledGameDetail]? = nil) {
        self.id = id
        self.league = league
        self.teamA = teamA
        self.teamB = teamB
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.startTime = startTime
        self.state = state
        self.blockName = blockName
        self.games = games
    }

    /// 라운드 표시 순서(내림차순 정렬 시 결승이 맨 앞에 오도록) — 한국어/영어 blockName 둘 다 대응.
    /// TournamentDetailView(MSI/Worlds)와 LeagueDetailView+History(일반 리그) 양쪽에서 공유.
    static func roundOrder(_ name: String) -> Int {
        let s = name.lowercased()
        // 한국어
        if s.contains("플레이-인") || s.contains("플레이인")            { return 0 }
        if s.contains("스위스") || s.contains("그룹 스테이지")           { return 10 }
        if s.contains("그룹")                                          { return 11 }
        if s == "16강"                                                  { return 20 }
        if s == "8강"                                                   { return 21 }
        if s == "4강"                                                   { return 22 }
        if s.contains("그랜드 파이널")                                   { return 24 }
        if s.contains("결승")                                          { return 23 }
        // 영어
        if s.contains("play-in") || s.contains("playin")              { return 0 }
        if s.contains("swiss") || s.contains("group stage")           { return 10 }
        if s.contains("group")                                         { return 11 }
        if s.contains("week") || s.hasPrefix("day")                    { return 12 }
        if s.contains("round of 16")                                   { return 20 }
        if s.contains("round of 8") || s.contains("quarter")           { return 21 }
        if s.contains("semi")                                          { return 22 }
        if s.contains("grand final")                                   { return 24 }
        if s.contains("final")                                         { return 23 }
        if s.contains("playoff") || s.contains("knockout") ||
           s.contains("bracket stage") || s.contains("elimination")    { return 19 }
        if s.contains("bracket")                                       { return 20 }
        return 15
    }

    /// 같은 라운드를 하나로 묶은 그룹 — `label`은 그 라운드에서 가장 많이 쓰인 blockName 표기.
    struct RoundGroup: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let matches: [Match]
    }

    /// blockName이 언어에 따라 다르게 들어올 수 있어서("8강" vs "Quarterfinals") 그대로 쓰면
    /// 같은 라운드가 칩 두 개로 중복 표시된다 — 실측 확인(historicalMatches엔 Leaguepedia 백필
    /// 원본(영어)과 Riot API `hl=ko-KR` 기반 syncHistoricalDaily 복사본(한국어)이 섞여 있음).
    /// 번호 없는 상위 카테고리 라운드명만 알려진 한/영 쌍으로 병합한다 — "Round 3"/"Bracket Round 2"
    /// 처럼 번호가 붙은 세부 라운드는 실제로 서로 다른 라운드라(실측: MSI Bracket Round 1~4 전부
    /// 별개 경기) 병합하면 안 되고, 이런 값은 전부 영어로만 나와서 애초에 언어 중복이 없다.
    private static let roundCanonicalKeys: [String: String] = [
        "결승": "finals", "finals": "finals", "그랜드 파이널": "grand final", "grand final": "grand final",
        "4강": "semifinals", "semifinals": "semifinals",
        "8강": "quarterfinals", "quarterfinals": "quarterfinals",
        "16강": "round of 16", "round of 16": "round of 16",
        "플레이-인": "play-in", "플레이인": "play-in", "play-in": "play-in",
        "스위스": "swiss stage", "swiss stage": "swiss stage", "swiss": "swiss stage",
        "그룹 스테이지": "group stage", "group stage": "group stage",
        "토너먼트 스테이지": "bracket stage", "bracket stage": "bracket stage",
    ]

    static func roundGroups(from matches: [Match]) -> [RoundGroup] {
        let byName = Dictionary(grouping: matches.compactMap { m -> (name: String, match: Match)? in
            guard let name = m.blockName else { return nil }
            return (name, m)
        }, by: { $0.name })
        .mapValues { $0.map(\.match) }

        var merged: [String: RoundGroup] = [:]   // canonicalKey -> 그룹
        var groups: [RoundGroup] = []
        for (name, ms) in byName {
            guard let canonical = roundCanonicalKeys[name.lowercased()] else {
                groups.append(RoundGroup(label: name, matches: ms))
                continue
            }
            if let existing = merged[canonical] {
                let label = ms.count > existing.matches.count ? name : existing.label
                merged[canonical] = RoundGroup(label: label, matches: existing.matches + ms)
            } else {
                merged[canonical] = RoundGroup(label: name, matches: ms)
            }
        }
        groups.append(contentsOf: merged.values)
        return groups.sorted { roundOrder($0.label) > roundOrder($1.label) }
    }
}

/// 백필된 과거 시즌 경기(datalisk.io) 한 게임(세트)의 상세 정보 — 밴 데이터는 없음(원본에 없음).
struct BackfilledGameDetail: Codable, Hashable {
    let number: Int
    let gameId: String
    let patch: Double?
    let vod: String?
    let blueTeamId: String
    let redTeamId: String
    let winnerTeamId: String?
    let blueTeamStats: TeamGameStats
    let redTeamStats: TeamGameStats
    let bluePlayers: [PlayerStats]
    let redPlayers: [PlayerStats]
}
