//
//  OracleElixirService+Stats.swift
//  LOLIVE
//
//  팀/선수 시즌 집계 스탯. 둘 다 리그당 요청 1번(전체 목록)으로 끝나고 24시간 캐싱되며,
//  같은 tournamentId 해석 경로(`+Seasons`)와 이름 매칭 헬퍼를 공유한다.
//

import Foundation

extension OracleElixirService {

    // MARK: - 이름 매칭

    /// Riot API와 OE는 서로 다른 소스라 이름 표기가 어긋나는 경우가 있다(실측 확인:
    /// 팀 "Gen.G Esports" ↔ "Gen.G", "NONGSHIM RED FORCE" ↔ "Nongshim RedForce"처럼
    /// 접미사·띄어쓰기 차이 — 선수 이름도 같은 종류의 표기 드리프트가 있을 수 있어 공용으로 씀).
    /// 단순 대소문자 무시 비교로는 통째로 매칭 실패할 수 있어, 영숫자만 남기고 정규화한 뒤
    /// 완전일치 → (그래도 안 맞으면) 부분일치 순으로 매칭한다.
    private static func matchByName<Row>(_ rows: [Row], target name: String, key: (Row) -> String) -> Row? {
        let target = normalizedName(name)
        guard !target.isEmpty else { return nil }

        if let exact = rows.first(where: { normalizedName(key($0)) == target }) {
            return exact
        }
        // 부분일치는 접미사가 붙은 경우 대응 — 너무 짧은 이름끼리 우연히 겹치는 걸 막기 위해
        // 최소 길이를 둔다.
        guard target.count >= 4 else { return nil }
        return rows.first { row in
            let candidate = normalizedName(key(row))
            guard candidate.count >= 4 else { return false }
            return candidate.contains(target) || target.contains(candidate)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - 팀 시즌 스탯

    /// `/stats/teams/byTournament` 원본 행 — 필드명은 OE 표기 그대로(AGT=평균 게임 시간(분),
    /// FB%=퍼스트블러드율, DRG%=드래곤 획득률, BN%=바론 획득률, GD15=15분 골드 격차, 그 외 확장
    /// 필드는 `TeamSeasonStats` 정의부 주석 참고). `%` 필드는 팀에 따라 `null`이 오기도 해서
    /// (예: 장로 드래곤이 안 나온 시즌의 ELD%) 전부 옵셔널 raw 문자열로 받고 변환한다.
    private struct TeamStatsRow: Codable {
        let Team: String
        let GP: Int
        let W: Int
        let L: Int
        let AGT: Double
        let K: Int
        let D: Int
        let KD: Double
        let CKPM: Double
        let GPR: Double
        let EGR: Double
        let MLR: Double
        let GD15: Double?
        let PPG: Double
        let WPM: Double
        let CWPM: Double
        let WCPM: Double
        private let gspdRaw: String?
        private let firstBloodRateRaw: String?
        private let firstTowerRateRaw: String?
        private let firstToThreeTowersRateRaw: String?
        private let heraldRateRaw: String?
        private let voidGrubsRateRaw: String?
        private let firstDragonRateRaw: String?
        private let dragonRateRaw: String?
        private let elderDragonRateRaw: String?
        private let firstBaronRateRaw: String?
        private let baronRateRaw: String?
        private let laneCsShareRaw: String?
        private let jungleCsShareRaw: String?

        enum CodingKeys: String, CodingKey {
            case Team, GP, W, L, AGT, K, D, KD, CKPM, GPR, EGR, MLR, GD15, PPG, WPM, CWPM, WCPM
            case gspdRaw = "GSPD"
            case firstBloodRateRaw = "FB%"
            case firstTowerRateRaw = "FT%"
            case firstToThreeTowersRateRaw = "F3T%"
            case heraldRateRaw = "HLD%"
            case voidGrubsRateRaw = "GRB%"
            case firstDragonRateRaw = "FD%"
            case dragonRateRaw = "DRG%"
            case elderDragonRateRaw = "ELD%"
            case firstBaronRateRaw = "FBN%"
            case baronRateRaw = "BN%"
            case laneCsShareRaw = "LNE%"
            case jungleCsShareRaw = "JNG%"
        }

        var killDeathRatio: Double { KD }
        var goldSpentPercentDiff: Double { OracleElixirService.percent(gspdRaw) ?? 0 }
        var firstBloodRate: Double { OracleElixirService.percent(firstBloodRateRaw) ?? 0 }
        var firstTowerRate: Double { OracleElixirService.percent(firstTowerRateRaw) ?? 0 }
        var firstToThreeTowersRate: Double { OracleElixirService.percent(firstToThreeTowersRateRaw) ?? 0 }
        var heraldRate: Double { OracleElixirService.percent(heraldRateRaw) ?? 0 }
        var voidGrubsRate: Double { OracleElixirService.percent(voidGrubsRateRaw) ?? 0 }
        var firstDragonRate: Double { OracleElixirService.percent(firstDragonRateRaw) ?? 0 }
        var dragonRate: Double { OracleElixirService.percent(dragonRateRaw) ?? 0 }
        var elderDragonRate: Double? { OracleElixirService.percent(elderDragonRateRaw) }
        var firstBaronRate: Double { OracleElixirService.percent(firstBaronRateRaw) ?? 0 }
        var baronRate: Double { OracleElixirService.percent(baronRateRaw) ?? 0 }
        var laneCsShare: Double { OracleElixirService.percent(laneCsShareRaw) ?? 0 }
        var jungleCsShare: Double { OracleElixirService.percent(jungleCsShareRaw) ?? 0 }
    }

    /// 팀 단위 시즌 집계 스탯.
    /// `tournamentId`를 명시하면(시즌 드롭다운) 그 시즌으로, 안 주면 현재 시즌으로 조회한다.
    func fetchTeamStats(team: Team, league: League, tournamentId explicitTournamentId: String? = nil) async -> TeamSeasonStats? {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return nil }
        guard let tournamentId = await resolveTournamentId(explicit: explicitTournamentId, oeLeagueName: oeLeagueName),
              let encoded = Self.queryEscaped(tournamentId)
        else { return nil }

        guard let rows: [TeamStatsRow] = await cachedFetch(
            .oeTeamStats(tournamentId: tournamentId),
            path: "/stats/teams/byTournament?tournament=\(encoded)"
        ) else { return nil }

        guard let row = Self.matchByName(rows, target: team.name, key: { $0.Team })
        else { return nil }

        return TeamSeasonStats(
            games: row.GP, wins: row.W, losses: row.L,
            avgGameMinutes: row.AGT,
            firstBloodRate: row.firstBloodRate,
            dragonRate: row.dragonRate,
            baronRate: row.baronRate,
            goldDiffAt15: row.GD15 ?? 0,
            kills: row.K, deaths: row.D,
            killDeathRatio: row.killDeathRatio,
            combinedKillsPerMinute: row.CKPM,
            goldPercentRating: row.GPR,
            goldSpentPercentDiff: row.goldSpentPercentDiff,
            earlyGameRating: row.EGR,
            midLateRating: row.MLR,
            firstTowerRate: row.firstTowerRate,
            firstToThreeTowersRate: row.firstToThreeTowersRate,
            platesPerGame: row.PPG,
            heraldRate: row.heraldRate,
            voidGrubsRate: row.voidGrubsRate,
            firstDragonRate: row.firstDragonRate,
            elderDragonRate: row.elderDragonRate,
            firstBaronRate: row.firstBaronRate,
            laneCsShare: row.laneCsShare,
            jungleCsShare: row.jungleCsShare,
            wardsPerMinute: row.WPM,
            controlWardsPerMinute: row.CWPM,
            wardsClearedPerMinute: row.WCPM
        )
    }

    // MARK: - 선수 시즌 스탯

    /// `/stats/players/byTournament` 원본 행 — 필드명은 OE 표기 그대로. `CTR%`는 정확한 정의를
    /// 못 찾아서(oracleselixir.com 자체 정의 페이지가 접근 차단됨) 의도적으로 안 씀 — 뜻이
    /// 불확실한 필드를 추측해서 라벨 붙이지 말 것.
    private struct PlayerStatsRow: Codable {
        let Player: String
        let Team: String
        let GP: Int
        let K: Int
        let D: Int
        let A: Int
        let KDA: Double
        let GD10: Double?
        let XPD10: Double?
        let CSD10: Double?
        let CSPM: Double
        let DPM: Double
        let TDPG: Double
        let EGPM: Double
        let STL: Int
        let WPM: Double
        let CWPM: Double
        let WCPM: Double
        private let winRateRaw: String?
        private let killParticipationRaw: String?
        private let killShareRaw: String?
        private let deathShareRaw: String?
        private let firstBloodRateRaw: String?
        private let csShareAt15Raw: String?
        private let damageShareRaw: String?
        private let damageShareAt15Raw: String?
        private let goldShareRaw: String?

        enum CodingKeys: String, CodingKey {
            case Player, Team, GP, K, D, A, KDA, GD10, XPD10, CSD10, CSPM, DPM, TDPG, EGPM, STL, WPM, CWPM, WCPM
            case winRateRaw = "W%"
            case killParticipationRaw = "KP"
            case killShareRaw = "KS%"
            case deathShareRaw = "DTH%"
            case firstBloodRateRaw = "FB%"
            case csShareAt15Raw = "CS%P15"
            case damageShareRaw = "DMG%"
            case damageShareAt15Raw = "D%P15"
            case goldShareRaw = "GOLD%"
        }

        var winRate: Double { OracleElixirService.percent(winRateRaw) ?? 0 }
        var killParticipation: Double { OracleElixirService.percent(killParticipationRaw) ?? 0 }
        var killShare: Double { OracleElixirService.percent(killShareRaw) ?? 0 }
        var deathShare: Double { OracleElixirService.percent(deathShareRaw) ?? 0 }
        var firstBloodRate: Double { OracleElixirService.percent(firstBloodRateRaw) ?? 0 }
        var csShareAt15: Double { OracleElixirService.percent(csShareAt15Raw) ?? 0 }
        var damageShare: Double { OracleElixirService.percent(damageShareRaw) ?? 0 }
        var damageShareAt15: Double { OracleElixirService.percent(damageShareAt15Raw) ?? 0 }
        var goldShare: Double { OracleElixirService.percent(goldShareRaw) ?? 0 }
    }

    /// 선수 단위 시즌 집계 스탯. 이름 매칭은 `player.summonerName`이 OE `Player` 필드와 표기가
    /// 다를 수 있어(대소문자·공백 등) `matchByName`으로 처리한다.
    /// `tournamentId`를 명시하면(시즌 드롭다운) 그 시즌으로, 안 주면 현재 시즌으로 조회한다.
    func fetchPlayerStats(player: Player, league: League, tournamentId explicitTournamentId: String? = nil) async -> PlayerOEStats? {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return nil }
        guard let tournamentId = await resolveTournamentId(explicit: explicitTournamentId, oeLeagueName: oeLeagueName),
              let encoded = Self.queryEscaped(tournamentId)
        else { return nil }

        guard let rows: [PlayerStatsRow] = await cachedFetch(
            .oePlayerStats(tournamentId: tournamentId),
            path: "/stats/players/byTournament?tournament=\(encoded)"
        ) else { return nil }

        guard let row = Self.matchByName(rows, target: player.summonerName, key: { $0.Player })
        else { return nil }

        return PlayerOEStats(
            games: row.GP, winRate: row.winRate,
            kills: row.K, deaths: row.D, assists: row.A, kda: row.KDA,
            killParticipation: row.killParticipation,
            killShare: row.killShare,
            deathShare: row.deathShare,
            firstBloodRate: row.firstBloodRate,
            goldDiffAt10: row.GD10, xpDiffAt10: row.XPD10, csDiffAt10: row.CSD10,
            csPerMin: row.CSPM,
            csShareAt15: row.csShareAt15,
            damagePerMin: row.DPM,
            damageShare: row.damageShare,
            damageShareAt15: row.damageShareAt15,
            totalDamagePerGame: row.TDPG,
            earnedGoldPerMin: row.EGPM,
            goldShare: row.goldShare,
            steals: row.STL,
            wardsPerMinute: row.WPM,
            controlWardsPerMinute: row.CWPM,
            wardsClearedPerMinute: row.WCPM
        )
    }
}
