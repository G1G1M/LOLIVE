//
//  LeaguesViewModel.swift
//  LOLIVE
//
//  리그 탭의 상태 관리 ViewModel.
//  기존 LeaguesView에 섞여 있던 데이터 로드/필터링/그룹핑 로직을 분리했다 (리팩토링 Phase 2).
//
//  [데이터 흐름]
//  load() → 디스크 캐시(24시간) 우선 표시 → Riot API 갱신 → 실패 시 캐시 유지
//

import Foundation
import Observation

@Observable
final class LeaguesViewModel {

    // MARK: - 상태

    var leagues: [League] = []
    var isLoading = false
    var loadFailed = false
    var searchText = ""

    @ObservationIgnored private let service = RiotEsportsService()

    /// 국제 대회로 취급하는 slug — TournamentDetailView로 라우팅되고 리스트 상단에 표시
    let internationalSlugs: Set<String> = ["worlds", "msi"]

    // MARK: - 파생 데이터

    /// 검색어 필터 적용된 리그 목록
    private var filtered: [League] {
        searchText.isEmpty ? leagues : leagues.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 지역별 그룹핑 + 정렬된 결과.
    /// "국제 대회" 그룹은 Worlds/MSI만 남기고 항상 최상단에 배치.
    var grouped: [(region: String, leagues: [League])] {
        let dict = Dictionary(grouping: filtered) { $0.region.isEmpty ? "기타" : $0.region }
        return dict
            .sorted { regionOrder($0.key) < regionOrder($1.key) }
            .compactMap { key, leagues in
                var list = leagues.sorted { $0.name < $1.name }
                if key == "국제 대회" {
                    list = list.filter { internationalSlugs.contains($0.slug) }
                }
                guard !list.isEmpty else { return nil }
                return (region: key, leagues: list)
            }
    }

    // MARK: - 데이터 로드

    func load() async {
        // 캐시 히트 시 즉시 표시하고 백그라운드에서 갱신 (스피너 없음)
        let hadCache: Bool
        if let cached: [League] = AppDiskCache.get(key: "leagues", maxAge: 24 * 3600), !cached.isEmpty {
            leagues = cached
            hadCache = true
        } else {
            isLoading = true
            hadCache = false
        }
        loadFailed = false

        let result = try? await service.fetchLeagues()
        if let result {
            leagues = result
        } else if !hadCache {
            // API 실패 + 캐시도 없음 → 에러 화면 표시
            loadFailed = true
        }
        isLoading = false
    }

    // MARK: - 지역 정렬 순서

    /// 리스트 섹션 표시 순서. 국제 대회 → 한국 → 중국 → … 순.
    private func regionOrder(_ region: String) -> Int {
        switch region {
        case "국제 대회":                return 0
        case "한국":                     return 1
        case "중국":                     return 2
        case "EMEA":                     return 3
        case "북미":                     return 4
        case "퍼시픽":                   return 5
        case "아메리카스":               return 6
        case "일본":                     return 7
        case "베트남":                   return 8
        case "브라질":                   return 9
        case "홍콩, 마카오, 대만":       return 10
        case "라틴 아메리카":            return 11
        case "라틴 아메리카 북부":       return 12
        case "라틴 아메리카 남부":       return 13
        case "오세아니아":               return 14
        case "독립 국가 연합 (CIS)":     return 15
        default:                         return 16
        }
    }
}
