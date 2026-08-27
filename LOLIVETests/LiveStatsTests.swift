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
