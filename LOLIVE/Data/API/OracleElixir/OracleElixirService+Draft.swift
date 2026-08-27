//
//  OracleElixirService+Draft.swift
//  LOLIVE
//
//  밴/드래프트 조회. Riot이 밴 데이터를 안 주는 경기의 1순위 폴백이고, 여기서도 실패하면
//  호출부(`MatchDetailViewModel`)가 Leaguepedia로 최종 폴백한다.
//

import Foundation

extension OracleElixirService {

    private struct SingleMatchRow: Codable {
        let game1Id: String?
        let game2Id: String?
        let game3Id: String?
        let game4Id: String?
        let game5Id: String?

        func gameId(number: Int) -> String? {
            switch number {
            case 1: return game1Id
            case 2: return game2Id
            case 3: return game3Id
            case 4: return game4Id
            case 5: return game5Id
            default: return nil
            }
        }
    }

    /// Riot 매치 id를 OE가 그대로 자기 matchId로 쓰는 걸 실측 확인함(`/matches/singleMatch/{riot의
    /// match.id}`가 바로 정확한 경기로 조회됨 — 팀명 퍼지매칭 같은 우회가 전혀 필요 없음).
    /// 30일 캐싱(완료 경기 시리즈 구성은 안 바뀜).
    private func oeGameId(riotMatchId: String, gameNumber: Int) async -> String? {
        let rows: [SingleMatchRow]? = await cachedFetch(
            .oeSingleMatch(riotMatchId: riotMatchId),
            path: "/matches/singleMatch/\(riotMatchId)"
        )
        return rows?.first?.gameId(number: gameNumber)
    }

    private struct DraftRow: Codable {
        let firstPick: String?
        let ban1: String?
        let ban2: String?
        let ban3: String?
        let ban4: String?
        let ban5: String?
        let ban6: String?
        let ban7: String?
        let ban8: String?
        let ban9: String?
        let ban10: String?

        var bansInOrder: [String?] { [ban1, ban2, ban3, ban4, ban5, ban6, ban7, ban8, ban9, ban10] }
    }

    /// 표준 토너먼트 드래프트 순서(밴 페이즈1: 선픽팀,상대,선픽팀,상대,선픽팀,상대 / 페이즈2:
    /// 상대,선픽팀,상대,선픽팀 — 실측: 실제 pick1~10의 champion을 comps.100/200과 대조해서
    /// 이 패턴이 정확히 맞는 것까지 확인함)으로 각 밴을 블루/레드에 배정한다. `team100=블루,
    /// team200=레드`는 Riot 엔진 표준이라 항상 고정.
    private static func splitBansBySide(_ bans: [String?], firstPick: String?) -> (blue: [String], red: [String])? {
        guard firstPick == "blue" || firstPick == "red" else { return nil }
        let firstIsBlue = firstPick == "blue"
        // index 0~9 = ban1~ban10. 선픽 팀이 도는 순서(true=선픽팀 차례).
        let isFirstSideTurn = [true, false, true, false, true, false, false, true, false, true]
        var blue: [String] = []
        var red: [String] = []
        for (i, ban) in bans.enumerated() {
            guard let ban, !ban.isEmpty else { continue }
            let isBlueTurn = isFirstSideTurn[i] == firstIsBlue
            if isBlueTurn { blue.append(ban) } else { red.append(ban) }
        }
        return (blue, red)
    }

    /// Riot이 밴 데이터를 안 주는 경기의 폴백. 실패하면 호출부가 Leaguepedia로 폴백한다.
    func fetchDraftBans(riotMatchId: String, gameNumber: Int) async -> (blue: [String], red: [String])? {
        guard let gameId = await oeGameId(riotMatchId: riotMatchId, gameNumber: gameNumber),
              let encoded = Self.pathEscaped(gameId)
        else { return nil }

        guard let draft: DraftRow = await cachedFetch(.oeDraft(gameId: gameId), path: "/drafts/\(encoded)")
        else { return nil }

        return Self.splitBansBySide(draft.bansInOrder, firstPick: draft.firstPick)
    }
}
