//
//  OracleElixirService+Seasons.swift
//  LOLIVE
//
//  리그의 시즌(토너먼트) 목록 조회와 "현재 시즌" 해석. 팀/선수 스탯, 공식 출전 명단이
//  전부 tournamentId를 기준으로 조회하기 때문에 그 앞단에 공통으로 놓인다.
//

import Foundation

extension OracleElixirService {

    private struct TournamentsByLeagueEntry: Codable {
        let id: String
        let name: String
        let startDate: String
    }

    /// `/tournaments/byLeague` 전체 응답(리그당 시즌 목록, 최신순). 응답 전체(~500KB)를
    /// 하루 캐싱해 리그별로 매번 다시 받지 않게 한다.
    private func tournamentsByLeague() async -> [String: [TournamentsByLeagueEntry]] {
        await cachedFetch(.oeTournamentsByLeague, path: "/tournaments/byLeague") ?? [:]
    }

    /// `fetchTeamStats`/`fetchPlayerStats`가 공유하는 tournamentId 결정 로직 — 명시적으로
    /// 넘어온 시즌(드롭다운 선택)이 있으면 그걸, 없으면 현재 시즌을 쓴다.
    func resolveTournamentId(explicit: String?, oeLeagueName: String) async -> String? {
        if let explicit { return explicit }
        return await currentTournamentId(oeLeagueName: oeLeagueName)
    }

    /// 리그의 가장 최근(현재) 시즌 토너먼트 ID — 시즌 목록의 첫 번째 항목.
    func currentTournamentId(oeLeagueName: String) async -> String? {
        guard let latest = await tournamentsByLeague()[oeLeagueName]?.first else { return nil }
        // LCO/LLA처럼 최근 시즌 데이터가 아예 안 들어온 리그도 있다(리그 개편·중단 등).
        // 너무 오래된 시즌 명단으로 필터링하면 지금 선수단을 전부 걸러내버리는(=선수 0명)
        // 역효과가 나서, 1년 넘게 지난 데이터는 없는 것으로 취급하고 로스터 fallback에 맡긴다.
        guard let startDate = Self.oeDateFmt.date(from: latest.startDate),
              Date().timeIntervalSince(startDate) < 365 * 24 * 3600
        else { return nil }
        return latest.id
    }

    /// "현재 시즌" 안의 라운드/구간 목록(예: LCK "2026 Rounds 3-4"/"2026 Road to MSI"/
    /// "2026 Rounds 1-2"/"2026 Cup"). 토너먼트 id가 "리그/연도 Season/구간" 형식이라
    /// (실측 확인: "LCK/2026 Season/Rounds 3-4"), 최신 항목과 접두사("LCK/2026 Season/")가
    /// 같은 것만 추려서 "지난 시즌"은 자동으로 빠진다. 목록은 이미 최신순이라 정렬 그대로 유지.
    func availableSeasons(league: League) async -> [OESeasonOption] {
        guard let oeLeagueName = Self.oracleElixirLeagueName(for: league) else { return [] }
        guard let entries = await tournamentsByLeague()[oeLeagueName], let latest = entries.first else { return [] }
        guard let prefix = Self.seasonPrefix(of: latest.id) else {
            return [OESeasonOption(id: latest.id, name: latest.name)]
        }
        return entries
            .filter { $0.id.hasPrefix(prefix) }
            .map { OESeasonOption(id: $0.id, name: $0.name) }
    }

    /// "LCK/2026 Season/Rounds 3-4" → "LCK/2026 Season/" (마지막 "/" 앞까지).
    private static func seasonPrefix(of tournamentId: String) -> String? {
        guard let lastSlash = tournamentId.range(of: "/", options: .backwards) else { return nil }
        return String(tournamentId[..<lastSlash.upperBound])
    }
}
