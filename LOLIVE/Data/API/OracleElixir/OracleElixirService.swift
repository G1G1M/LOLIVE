//
//  OracleElixirService.swift
//  LOLIVE
//
//  Oracle's Elixir(oe.datalisk.io — 과거 시즌 백필에도 쓰는 비공식 API) 연동의 공통 부분.
//  Riot API는 은퇴/개편된 옛날 팀 선수를 아예 조회할 방법이 없고(현재 로스터만 제공),
//  기존에 쓰던 Leaguepedia는 레이트리밋이 잦아(공식 문서 없음, 실측으로 자주 확인됨)
//  같은 API 키를 공유하는 이 엔드포인트로 교체했다.
//  키는 oracleselixir.com 프로덕션 JS 번들에 공개돼 있는 값(리버스 엔지니어링으로 확인,
//  historicalBackfill과 동일한 성격의 비공식 연동).
//
//  실제 조회 기능은 용도별 extension 파일로 나뉘어 있다:
//    +Seasons       — 시즌(토너먼트) 목록·현재 시즌 해석
//    +Stats         — 팀/선수 시즌 집계 스탯
//    +Players       — 프로필 사진, 리그 공식 출전 명단, 게임별 챔피언 픽
//    +Draft         — 밴/드래프트
//    +LiveReconcile — stuck 라이브 경기 보정
//    +LeagueMapping — Riot 리그 → OE 리그 이름 변환
//

import Foundation

/// 시즌/구간 선택 드롭다운에 쓰는 값 — `OracleElixirService.availableSeasons(league:)` 참고.
struct OESeasonOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct OracleElixirService: Sendable {

    static let shared = OracleElixirService()

    private let apiBase = "https://oe.datalisk.io"
    /// 선수 프로필 사진 URL을 조립할 때만 쓴다(`+Players`).
    let cdnBase = "https://cdn.datalisk.io"
    private let apiKey = "f561197a-82ea-4e54-acd2-386979018a7a"

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 10
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    static let oeDateFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - 요청 헬퍼

    /// OE 엔드포인트 1회 조회. 모든 요청이 `x-api-key` 헤더 + 200 확인 + JSON 디코딩이라
    /// 같은 코드가 엔드포인트마다 반복되던 걸 여기 하나로 모았다.
    /// 실패(네트워크·상태코드·디코딩)는 전부 nil — 호출부가 폴백을 결정한다.
    func fetch<T: Decodable>(_ path: String) async -> T? {
        guard let url = URL(string: apiBase + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(T.self, from: data)
        else { return nil }
        return decoded
    }

    /// 디스크 캐시 우선 조회 후 없을 때만 네트워크. 키/TTL은 `CacheKey`에 정의된 값을 쓴다.
    func cachedFetch<T: Codable>(_ key: CacheKey, path: String) async -> T? {
        if let cached: T = AppDiskCache.get(key) { return cached }
        guard let fresh: T = await fetch(path) else { return nil }
        AppDiskCache.set(key, value: fresh)
        return fresh
    }

    /// URL 경로 세그먼트로 넣을 값 이스케이프(선수 이름·토너먼트 id 등에 공백/기호가 들어온다).
    static func pathEscaped(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    /// 쿼리 파라미터 값 이스케이프.
    static func queryEscaped(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }

    /// OE가 비율을 `"62.5%"` 같은 문자열로 주는 필드 변환(→ 0.625).
    /// 팀에 따라 `null`이 오는 필드가 있어(예: 장로 드래곤이 안 나온 시즌의 `ELD%`) 옵셔널을 받는다.
    static func percent(_ raw: String?) -> Double? {
        guard let raw, let value = Double(raw.replacingOccurrences(of: "%", with: ""))
        else { return nil }
        return value / 100
    }
}
