//
//  LOLIVETests.swift
//  LOLIVETests
//

import Testing
@testable import LOLIVE

// MARK: - escapeSql

@Suite("escapeSql") struct EscapeSqlTests {
    let svc = LeaguepediaService.shared

    @Test func noSpecialChars() {
        #expect(svc.escapeSql("Faker") == "Faker")
    }

    @Test func singleQuote() {
        #expect(svc.escapeSql("O'Brien") == "O\\'Brien")
    }

    @Test func multipleSingleQuotes() {
        #expect(svc.escapeSql("It's O'Brien") == "It\\'s O\\'Brien")
    }

    @Test func emptyString() {
        #expect(svc.escapeSql("") == "")
    }
}

// MARK: - parseBans

@Suite("parseBans") struct ParseBansTests {
    let svc = LeaguepediaService.shared

    @Test func normalCommaSeparated() {
        #expect(svc.parseBans("Zed,Yasuo,Lux") == ["Zed", "Yasuo", "Lux"])
    }

    @Test func trailingWhitespace() {
        #expect(svc.parseBans("Zed, Yasuo , Lux") == ["Zed", "Yasuo", "Lux"])
    }

    @Test func singleChampion() {
        #expect(svc.parseBans("Orianna") == ["Orianna"])
    }

    @Test func emptyString() {
        #expect(svc.parseBans("").isEmpty)
    }
}

// MARK: - computeStats

@Suite("computeStats") struct ComputeStatsTests {
    let svc = LeaguepediaService.shared

    // 행 하나를 편리하게 만드는 헬퍼. winner: "1" or "2"
    private func row(k: String, d: String, a: String,
                     winner: String, gl: String, cs: String) -> [String: String] {
        ["K": k, "D": d, "A": a,
         "W": winner, "T1": "MY", "T2": "OPP", "MyTeam": "MY",
         "GL": gl, "CS": cs]
    }

    @Test func basicStats() {
        // 2게임 모두 승, KDA·CS/분 계산
        let rows = [
            row(k: "4", d: "2", a: "6", winner: "1", gl: "30", cs: "180"),
            row(k: "6", d: "2", a: "4", winner: "1", gl: "32", cs: "256"),
        ]
        let s = svc.computeStats(from: rows)
        #expect(s.games == 2)
        #expect(s.winRate == 1.0)
        #expect(s.avgKills == 5.0)
        #expect(s.avgDeaths == 2.0)
        #expect(s.avgAssists == 5.0)
        #expect(s.kdaRatio == 5.0)  // (5+5)/2
    }

    @Test func winRate_halfWins() {
        // row1 승(W=1, MyTeam=T1), row2 패(W=2, MyTeam=T1이지만 T2=OPP ≠ MY)
        let rows = [
            row(k: "3", d: "3", a: "3", winner: "1", gl: "30", cs: "180"),
            row(k: "3", d: "3", a: "3", winner: "2", gl: "30", cs: "180"),
        ]
        #expect(svc.computeStats(from: rows).winRate == 0.5)
    }

    @Test func perfectKDA_zeroDeaths() {
        // 데스 0 → KDA = kills + assists (나누기 없음)
        let rows = [row(k: "5", d: "0", a: "3", winner: "1", gl: "30", cs: "200")]
        let s = svc.computeStats(from: rows)
        #expect(s.avgDeaths == 0.0)
        #expect(s.kdaRatio == 8.0)  // 5 + 3
    }

    @Test func csPerMin_excludesZeroGL() {
        // GL=0인 게임은 CS/분 계산에서 제외
        let rows = [
            row(k: "3", d: "1", a: "5", winner: "1", gl: "0",  cs: "999"),
            row(k: "4", d: "2", a: "3", winner: "1", gl: "30", cs: "210"),
        ]
        let s = svc.computeStats(from: rows)
        #expect(abs(s.avgCSPerMin - 7.0) < 0.001)  // 210/30 = 7.0 (첫 번째 제외)
    }

    @Test func singleRow() {
        let rows = [row(k: "6", d: "1", a: "9", winner: "1", gl: "35", cs: "245")]
        let s = svc.computeStats(from: rows)
        #expect(s.games == 1)
        #expect(s.winRate == 1.0)
        #expect(s.avgKills == 6.0)
        #expect(s.kdaRatio == 15.0)    // (6+9)/1
        #expect(abs(s.avgCSPerMin - 7.0) < 0.001)  // 245/35
    }
}

// MARK: - findStats

@Suite("findStats") struct FindStatsTests {
    let svc = LeaguepediaService.shared

    private func mock(games: Int = 10) -> PlayerSeasonStats {
        PlayerSeasonStats(games: games, winRate: 0.6,
                          avgKills: 4, avgDeaths: 2, avgAssists: 6,
                          kdaRatio: 5, avgCSPerMin: 7)
    }

    @Test func exactMatch() {
        let dict = ["Faker": mock(games: 10)]
        #expect(svc.findStats(in: dict, summonerName: "Faker")?.games == 10)
    }

    @Test func parenthesisFallback() {
        // Leaguepedia에 "Faker (T1)"으로 저장, Riot은 "Faker"로 전달하는 경우
        let dict = ["Faker (T1)": mock(games: 8)]
        #expect(svc.findStats(in: dict, summonerName: "Faker")?.games == 8)
    }

    @Test func caseInsensitive() {
        // Riot "Hades1" vs Leaguepedia "HADES1"
        let dict = ["HADES1": mock(games: 7)]
        #expect(svc.findStats(in: dict, summonerName: "Hades1")?.games == 7)
    }

    @Test func caseInsensitiveParenthesis() {
        let dict = ["HADES1 (DRX)": mock(games: 6)]
        #expect(svc.findStats(in: dict, summonerName: "hades1")?.games == 6)
    }

    @Test func noMatch_returnsNil() {
        let dict = ["Faker": mock()]
        #expect(svc.findStats(in: dict, summonerName: "Chovy") == nil)
    }

    @Test func exactPrecedesParenthesis() {
        // 정확 일치가 "(팀)" 폴백보다 우선해야 함
        let dict = ["Faker": mock(games: 10), "Faker (T1)": mock(games: 5)]
        #expect(svc.findStats(in: dict, summonerName: "Faker")?.games == 10)
    }
}

// MARK: - findPicks

@Suite("findPicks") struct FindPicksTests {
    let svc = LeaguepediaService.shared

    private func picks(count: Int) -> [ChampionPickEntry] {
        (0..<count).map {
            ChampionPickEntry(champion: "Champ\($0)", kills: 3, deaths: 1, assists: 5, won: true)
        }
    }

    @Test func exactMatch() {
        let dict = ["Ruler": picks(count: 3)]
        #expect(svc.findPicks(in: dict, summonerName: "Ruler").count == 3)
    }

    @Test func noMatch_returnsEmpty() {
        let dict = ["Ruler": picks(count: 3)]
        #expect(svc.findPicks(in: dict, summonerName: "Gumayusi").isEmpty)
    }

    @Test func caseInsensitive() {
        let dict = ["RULER": picks(count: 2)]
        #expect(svc.findPicks(in: dict, summonerName: "ruler").count == 2)
    }

    @Test func parenthesisFallback() {
        let dict = ["Ruler (GEN)": picks(count: 4)]
        #expect(svc.findPicks(in: dict, summonerName: "Ruler").count == 4)
    }
}

// MARK: - deduplicated

@Suite("deduplicated") struct DeduplicatedTests {
    let svc = LeaguepediaService.shared

    private let league = League(id: "lck", slug: "lck", name: "LCK", region: "Korea", imageURL: nil)
    private let t1 = Team(id: "T1", name: "T1", code: "T1", imageURL: nil)
    private let gen = Team(id: "GEN", name: "Gen.G", code: "GEN", imageURL: nil)

    private func match(id: String) -> Match {
        Match(id: id, league: league, teamA: t1, teamB: gen,
              scoreA: 0, scoreB: 0, startTime: .now, state: .unstarted)
    }

    @Test func noDuplicates_unchanged() {
        let matches = ["a", "b", "c"].map { match(id: $0) }
        #expect(svc.deduplicated(matches).count == 3)
    }

    @Test func removesDuplicates() {
        let matches = ["a", "b", "a", "c"].map { match(id: $0) }
        let result = svc.deduplicated(matches)
        #expect(result.count == 3)
        #expect(result.map(\.id) == ["a", "b", "c"])
    }

    @Test func keepsFirstOccurrence() {
        let matches = ["x", "x", "x"].map { match(id: $0) }
        #expect(svc.deduplicated(matches).count == 1)
        #expect(svc.deduplicated(matches).first?.id == "x")
    }

    @Test func emptyInput() {
        #expect(svc.deduplicated([]).isEmpty)
    }
}
