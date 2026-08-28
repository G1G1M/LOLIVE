//
//  LiveStatsTests.swift
//  LOLIVETests
//
//  Riot 라이브 스탯 피드 파싱을 실측 응답(LiveStatsFixtures)으로 고정한다.
//

import Testing
import Foundation
@testable import LOLIVE

// MARK: - window 파싱

@Suite("LiveStatsService.decodeWindow") struct DecodeWindowTests {
    let svc = LiveStatsService()

    private func window() throws -> GameWindow {
        try svc.decodeWindow(LiveStatsFixtures.windowData)
    }

    @Test func 팀_식별자와_게임상태를_읽는다() throws {
        let w = try window()
        #expect(w.gameId == "117030752644841578")
        #expect(w.gameState == "in_game")
        #expect(w.blueTeamId == "100725845022060229")
        #expect(w.redTeamId == "102747101565183056")
    }

    @Test func 팀_단위_스탯을_읽는다() throws {
        let w = try window()
        #expect(w.blueTeamStats.totalGold == 40523)
        #expect(w.blueTeamStats.totalKills == 6)
        #expect(w.blueTeamStats.towers == 2)
        #expect(w.redTeamStats.totalGold == 48664)
        #expect(w.redTeamStats.towers == 5)
    }

    /// 예전엔 dragons를 개수로만 접어버려서 어떤 드래곤을 먹었는지 알 수 없었다.
    @Test func 드래곤은_개수와_종류를_모두_보관한다() throws {
        let w = try window()
        #expect(w.blueTeamStats.dragons == 1)
        #expect(w.blueTeamStats.dragonTypes == ["hextech"])
        #expect(w.redTeamStats.dragons == 3)
        #expect(w.redTeamStats.dragonTypes == ["infernal", "cloud", "cloud"])
    }

    @Test func 드래곤_종류를_DragonType으로_해석한다() throws {
        let w = try window()
        #expect(w.blueTeamStats.recognizedDragons == [.hextech])
        #expect(w.redTeamStats.recognizedDragons == [.infernal, .cloud, .cloud])
    }

    @Test func 선수_스탯을_읽는다() throws {
        let w = try window()
        let clear = try #require(w.bluePlayers.first { $0.summonerName == "BFX Clear" })
        #expect(clear.championId == "Jayce")
        #expect(clear.role == "top")
        #expect(clear.kills == 2)
        #expect(clear.deaths == 3)
        #expect(clear.assists == 3)
        #expect(clear.totalGold == 9735)
        #expect(clear.creepScore == 226)
        #expect(clear.level == 15)
    }

    /// 새로 파싱하기 시작한 필드 — 체력이 깎인 선수와 만피인 선수가 구분돼야 한다.
    @Test func 선수_체력을_읽는다() throws {
        let w = try window()
        let raptor = try #require(w.bluePlayers.first { $0.summonerName == "BFX Raptor" })
        #expect(raptor.currentHealth == 1563)
        #expect(raptor.maxHealth == 2542)

        let taeyoon = try #require(w.bluePlayers.first { $0.summonerName == "BFX Taeyoon" })
        #expect(taeyoon.currentHealth == taeyoon.maxHealth)
    }

    @Test func 양_팀_다섯명씩_읽는다() throws {
        let w = try window()
        #expect(w.bluePlayers.count == 5)
        #expect(w.redPlayers.count == 5)
    }
}

// MARK: - 캐시 호환

@Suite("GameWindow 캐시 호환") struct GameWindowCodableTests {

    /// GameWindowCache는 만료 없는 영구 캐시다. 모델에 필드를 추가할 때 논옵셔널로 넣으면
    /// 예전에 저장된 파일이 통째로 디코딩 실패해 완료 경기 캐시가 전부 날아간다.
    /// 새 필드가 없는 옛 JSON도 계속 읽히는지 고정해둔다.
    @Test func 새_필드가_없는_옛_캐시도_읽힌다() throws {
        let legacy = #"""
        {"gameId":"g1","gameState":"finished","blueTeamId":"b","redTeamId":"r",
         "bluePlayers":[{"participantId":1,"summonerName":"A","championId":"Ahri","role":"mid",
                         "kills":1,"deaths":2,"assists":3,"totalGold":100,"creepScore":10,"level":5}],
         "redPlayers":[],
         "blueTeamStats":{"totalGold":1,"towers":2,"barons":3,"totalKills":4,"dragons":5,"inhibitors":6},
         "redTeamStats":{"totalGold":0,"towers":0,"barons":0,"totalKills":0,"dragons":0,"inhibitors":0}}
        """#
        let w = try JSONDecoder().decode(GameWindow.self, from: Data(legacy.utf8))

        #expect(w.gameId == "g1")
        #expect(w.blueTeamStats.dragons == 5)
        #expect(w.blueTeamStats.dragonTypes == nil)
        #expect(w.blueTeamStats.recognizedDragons.isEmpty)
        #expect(w.bluePlayers.first?.currentHealth == nil)
    }

    @Test func 인코딩_디코딩_왕복에서_새_필드가_보존된다() throws {
        let svc = LiveStatsService()
        let original = try svc.decodeWindow(LiveStatsFixtures.windowData)
        let round = try JSONDecoder().decode(GameWindow.self,
                                             from: JSONEncoder().encode(original))
        #expect(round.redTeamStats.dragonTypes == ["infernal", "cloud", "cloud"])
        #expect(round.bluePlayers.first { $0.summonerName == "BFX Raptor" }?.currentHealth == 1563)
    }
}

// MARK: - DragonType

@Suite("DragonType") struct DragonTypeTests {

    @Test func 피드_문자열을_해석한다() {
        #expect(DragonType(feedValue: "infernal") == .infernal)
        #expect(DragonType(feedValue: "CLOUD") == .cloud)
        #expect(DragonType(feedValue: " elder ") == .elder)
    }

    /// 모르는 종류를 추측해서 라벨 붙이면 안 된다 — 조용히 틀린 정보를 보여주게 된다.
    @Test func 모르는_값은_nil() {
        #expect(DragonType(feedValue: "quantum") == nil)
        #expect(DragonType(feedValue: "") == nil)
    }

    @Test func 모든_종류가_라벨과_아이콘을_갖는다() {
        for dragon in DragonType.allCases {
            #expect(!dragon.shortLabel.isEmpty)
            #expect(!dragon.symbolName.isEmpty)
        }
    }
}

// MARK: - details 파싱

@Suite("LiveStatsService.decodeDetails") struct DecodeDetailsTests {
    let svc = LiveStatsService()

    private func detail() throws -> GameLiveDetail {
        try svc.decodeDetails(LiveStatsFixtures.detailsData, gameId: "117030752644841578")
    }

    @Test func 기여도와_시야를_읽는다() throws {
        let clear = try #require(detail().player(1))
        #expect(abs(clear.killParticipation - 0.8333333333333334) < 0.0001)
        #expect(abs(clear.championDamageShare - 0.2835886953576407) < 0.0001)
        #expect(clear.wardsPlaced == 7)
        #expect(clear.wardsDestroyed == 4)
    }

    @Test func 전투_스탯을_읽는다() throws {
        let clear = try #require(detail().player(1))
        #expect(clear.attackDamage == 300)
        #expect(clear.abilityPower == 0)
        #expect(clear.armor == 113)
        #expect(clear.magicResistance == 47)
        #expect(clear.attackSpeed == 144)
    }

    /// 아이템은 숫자 ID로만 오고, 빈 슬롯은 0이라 걸러서 담는다.
    @Test func 아이템과_룬과_스킬순서를_읽는다() throws {
        let clear = try #require(detail().player(1))
        #expect(clear.items == [1055, 3047, 3161, 3134, 3364, 1037])
        #expect(clear.items.allSatisfy { $0 > 0 })
        #expect(clear.perkStyleId == 8400)
        #expect(clear.perkSubStyleId == 8300)
        #expect(clear.perks.count == 8)
        #expect(clear.abilities.first == "R")
    }

    @Test func 프레임_시각을_읽는다() throws {
        #expect(try detail().capturedAt != nil)
    }

    /// details 응답에는 events / gameTime 필드가 없다(2026-08-27 실측).
    /// 킬 타임라인과 인게임 시계가 여기 의존하다 조용히 죽었던 걸 기록해둔다.
    /// 나중에 Riot이 되살리면 이 테스트가 실패하면서 알려준다.
    @Test func 응답에_events와_gameTime이_없다() throws {
        let json = try #require(
            try JSONSerialization.jsonObject(with: LiveStatsFixtures.detailsData) as? [String: Any]
        )
        let frames = try #require(json["frames"] as? [[String: Any]])
        #expect(frames.allSatisfy { $0["events"] == nil })
        #expect(frames.allSatisfy { $0["gameTime"] == nil })
    }
}

// MARK: - startingTime 정렬

@Suite("LiveStatsService.alignedToTenSeconds") struct StartingTimeAlignmentTests {

    /// 피드는 startingTime이 10초 경계에 정렬돼 있지 않으면 무조건 400을 준다(실측 확인).
    /// window 응답의 rfc460Timestamp(예: 16:30:09.879Z)를 그대로 되돌려 보내다가
    /// 선수 상세가 항상 실패했던 적이 있다.
    @Test func 소수점_초를_10초_경계로_내린다() {
        let fmt = LiveStatsService.feedTimestamp
        let messy = try! #require(fmt.date(from: "2026-08-27T16:30:09.879Z"))
        let aligned = LiveStatsService.alignedToTenSeconds(messy)
        #expect(fmt.string(from: aligned) == "2026-08-27T16:30:00.000Z")
    }

    @Test func 이미_정렬된_시각은_그대로_둔다() {
        let fmt = LiveStatsService.feedTimestamp
        let clean = try! #require(fmt.date(from: "2026-08-27T16:30:10.000Z"))
        #expect(LiveStatsService.alignedToTenSeconds(clean) == clean)
    }

    @Test func 항상_10초의_배수가_된다() {
        let fmt = LiveStatsService.feedTimestamp
        for sec in ["00.000", "03.500", "09.999", "10.001", "59.999"] {
            let d = try! #require(fmt.date(from: "2026-08-27T16:30:\(sec)Z"))
            let aligned = LiveStatsService.alignedToTenSeconds(d)
            #expect(aligned.timeIntervalSince1970.truncatingRemainder(dividingBy: 10) == 0)
            #expect(aligned <= d)   // 미래로 넘어가면 아직 없는 프레임을 요청하게 된다
        }
    }
}

// MARK: - 맞라이너 대결

@Suite("LaneMatchup") struct LaneMatchupTests {
    let svc = LiveStatsService()

    private func matchup(_ name: String) throws -> LaneMatchup? {
        let window = try svc.decodeWindow(LiveStatsFixtures.windowData)
        let detail = try svc.decodeDetails(LiveStatsFixtures.detailsData, gameId: window.gameId)
        return LaneMatchup.build(gameNumber: 1, window: window, detail: detail, summonerName: name)
    }

    /// 같은 role 을 반대편에서 찾는다 — 챔피언이나 순서로 추측하지 않는다.
    @Test func 같은_라인_상대를_짝짓는다() throws {
        let m = try #require(try matchup("BFX Clear"))     // 블루 탑 Jayce
        #expect(m.role == "top")
        #expect(m.me.championId == "Jayce")
        #expect(m.opponent?.championId == "Camille")   // 레드 탑
        #expect(m.opponent?.summonerName == "NS Kingen")
        #expect(m.me.isBlue == true)
        #expect(m.opponent?.isBlue == false)
    }

    /// 봇·서포터도 같은 규칙으로 짝지어져야 한다 — 포지션별 예외를 두지 않는다.
    @Test func 봇과_서포터도_같은_규칙으로_짝지어진다() throws {
        let bot = try #require(try matchup("BFX Taeyoon"))
        #expect(bot.role == "bottom")
        #expect(bot.opponent?.summonerName == "NS Diable")

        let sup = try #require(try matchup("BFX Kellin"))
        #expect(sup.role == "support")
        #expect(sup.opponent?.summonerName == "NS Lehends")
    }

    @Test func 레드팀_선수도_반대로_짝지어진다() throws {
        let m = try #require(try matchup("NS Scout"))       // 레드 미드
        #expect(m.me.isBlue == false)
        #expect(m.opponent?.summonerName == "BFX VicLa")
        #expect(m.opponent?.isBlue == true)
    }

    @Test func 없는_선수는_nil() throws {
        #expect(try matchup("존재하지 않는 선수") == nil)
    }

    /// 팀 5명 중 딜 비중 순위. 맞라이너 비교만으로는 "우리 팀에서 몇 번째 딜러"가 안 보인다.
    @Test func 팀_내_딜비중_순위를_센다() throws {
        let ranks = try ["BFX Clear", "BFX Raptor", "BFX VicLa", "BFX Taeyoon", "BFX Kellin"]
            .compactMap { try matchup($0) }
            .map(\.damageShareRank)
        #expect(ranks.count == 5)
        #expect(Set(ranks) == Set(1...5))              // 1~5위가 중복 없이 다 나온다
        let support = try #require(try matchup("BFX Kellin"))
        #expect(support.damageShareRank == 5)          // 서포터가 딜 비중 꼴찌
    }

    /// 골드 격차는 맞라이너 기준으로 서로 부호만 반대여야 한다.
    @Test func 골드_격차는_서로_부호가_반대다() throws {
        let clear = try #require(try matchup("BFX Clear"))
        let kingen = try #require(try matchup("NS Kingen"))
        let a = try #require(clear.goldDifference)
        let b = try #require(kingen.goldDifference)
        #expect(a == -b)
    }
}

// MARK: - 세트 시작 직후(전부 0) 처리

@Suite("LaneMatchup 0값 처리") struct LaneMatchupZeroTests {

    private func detail(_ pid: Int, gold: Int, cs: Int, dmg: Double) -> PlayerLiveDetail {
        PlayerLiveDetail(participantId: pid, level: 1, kills: 0, deaths: 0, assists: 0,
                         totalGoldEarned: gold, creepScore: cs,
                         killParticipation: 0, championDamageShare: dmg,
                         wardsPlaced: 0, wardsDestroyed: 0,
                         attackDamage: 0, abilityPower: 0, armor: 0, magicResistance: 0,
                         attackSpeed: 0, criticalChance: 0, lifeSteal: 0, tenacity: 0,
                         items: [], perkStyleId: nil, perkSubStyleId: nil, perks: [], abilities: [])
    }

    private func player(_ pid: Int, blue: Bool) -> PlayerStats {
        PlayerStats(participantId: pid, summonerName: blue ? "나" : "상대", championId: "Ahri",
                    role: "mid", kills: 0, deaths: 0, assists: 0, totalGold: 0,
                    creepScore: 0, level: 1, currentHealth: nil, maxHealth: nil)
    }

    private func makeWindow() -> GameWindow {
        let empty = TeamGameStats(totalGold: 0, towers: 0, barons: 0, totalKills: 0,
                                  dragons: 0, inhibitors: 0, dragonTypes: nil)
        return GameWindow(gameId: "g", gameState: "in_game", blueTeamId: "b", redTeamId: "r",
                          bluePlayers: [player(1, blue: true)], redPlayers: [player(6, blue: false)],
                          blueTeamStats: empty, redTeamStats: empty,
                          gameTime: nil, lastFrameTimestamp: nil, patchVersion: nil)
    }

    private func build(mine: PlayerLiveDetail, theirs: PlayerLiveDetail) -> LaneMatchup? {
        LaneMatchup.build(gameNumber: 1, window: makeWindow(),
                          detail: GameLiveDetail(gameId: "g", capturedAt: nil, players: [mine, theirs]),
                          summonerName: "나")
    }

    /// 막 시작한 세트는 양쪽 다 0이다. 이때 격차를 0으로 보여주면 "동등하다"로 읽힌다.
    @Test func 전부_0이면_격차를_보여주지_않는다() throws {
        let m = try #require(build(mine: detail(1, gold: 0, cs: 0, dmg: 0),
                                   theirs: detail(6, gold: 0, cs: 0, dmg: 0)))
        #expect(m.goldDifference == nil)
        #expect(m.showsDamageShareRank == false)
    }

    @Test func 값이_생기면_격차를_계산한다() throws {
        let ahead = try #require(build(mine: detail(1, gold: 5000, cs: 100, dmg: 0.3),
                                       theirs: detail(6, gold: 4000, cs: 80, dmg: 0.2)))
        #expect(ahead.goldDifference == 1000)
        #expect(ahead.showsDamageShareRank == true)

        let behind = try #require(build(mine: detail(1, gold: 3000, cs: 60, dmg: 0.1),
                                        theirs: detail(6, gold: 4000, cs: 80, dmg: 0.2)))
        #expect(behind.goldDifference == -1000)
    }
}


// MARK: - 라이브 최신 시점

@Suite("LiveStatsService.liveEdge") struct LiveEdgeTests {

    /// startingTime 을 비우면 게임 "시작" 프레임이 온다. 진행 중인 경기에서 그렇게 부르면
    /// 폴링을 아무리 돌려도 골드 0·킬 0 만 돌아온다 — 실제로 그 상태로 배포돼 있었다.
    @Test func 지금보다_충분히_과거여야_한다() {
        let now = Date()
        let edge = LiveStatsService.liveEdge(now: now)
        let behind = now.timeIntervalSince(edge)
        // 피드는 약 3분 25초 이내를 400으로 거절한다. 여유가 있어야 한다.
        let farEnough = behind > 205
        let notTooFar = behind < 600
        #expect(farEnough)
        #expect(notTooFar)
    }

    @Test func 라이브_시점도_10초_경계에_정렬된다() {
        let edge = LiveStatsService.liveEdge(now: Date())
        let remainder = edge.timeIntervalSince1970.truncatingRemainder(dividingBy: 10)
        #expect(remainder == 0)
    }
}

// MARK: - 패치 버전

@Suite("GameWindow.shortPatch") struct PatchVersionTests {

    @Test func 실측_응답에서_패치를_읽는다() throws {
        let window = try LiveStatsService().decodeWindow(LiveStatsFixtures.windowData)
        let full = window.patchVersion
        let short = window.shortPatch
        #expect(full == "16.16.809.3269")
        #expect(short == "16.16")
    }

    @Test func 패치가_없는_옛_캐시는_nil() throws {
        let legacy = LegacyWindowJSON.noPatch
        let window = try JSONDecoder().decode(GameWindow.self, from: Data(legacy.utf8))
        let full = window.patchVersion
        let short = window.shortPatch
        #expect(full == nil)
        #expect(short == nil)
    }
}

enum LegacyWindowJSON {
    static let noPatch = """
    {"gameId":"g","gameState":"finished","blueTeamId":"b","redTeamId":"r",
     "bluePlayers":[],"redPlayers":[],
     "blueTeamStats":{"totalGold":0,"towers":0,"barons":0,"totalKills":0,"dragons":0,"inhibitors":0},
     "redTeamStats":{"totalGold":0,"towers":0,"barons":0,"totalKills":0,"dragons":0,"inhibitors":0}}
    """
}
