//
//  OracleElixirService.swift
//  LOLIVE
//
//  Oracle's Elixir(oe.datalisk.io — 과거 시즌 백필에도 쓰는 비공식 API)에서 선수 프로필
//  사진을 가져온다. Riot API는 은퇴/개편된 옛날 팀 선수를 아예 조회할 방법이 없고
//  (현재 로스터만 제공), 기존에 쓰던 Leaguepedia는 레이트리밋이 잦아(공식 문서 없음,
//  실측으로 자주 확인됨) 같은 API 키를 공유하는 이 엔드포인트로 교체했다.
//  키는 oracleselixir.com 프로덕션 JS 번들에 공개돼 있는 값(리버스 엔지니어링으로 확인,
//  historicalBackfill과 동일한 성격의 비공식 연동).
//

import Foundation

struct OracleElixirService: Sendable {

    static let shared = OracleElixirService()

    private let apiBase = "https://oe.datalisk.io"
    private let cdnBase = "https://cdn.datalisk.io"
    private let apiKey = "f561197a-82ea-4e54-acd2-386979018a7a"

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 10
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    private struct PlayerResponse: Decodable {
        let playerPhoto: String?
    }

    /// 선수 프로필 사진 URL 반환. 은퇴/현역 여부와 무관하게 조회 가능(실측 확인).
    func fetchPlayerImageURL(summonerName: String) async -> URL? {
        let cacheKey = CacheKey.oracleElixirPlayerImage(summonerName: summonerName)
        if let cached: String = AppDiskCache.get(cacheKey) {
            return cached.isEmpty ? nil : URL(string: cached)
        }

        guard let encoded = summonerName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(apiBase)/players/\(encoded)")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        guard let (data, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let player = try? JSONDecoder().decode(PlayerResponse.self, from: data),
              let photo = player.playerPhoto, !photo.isEmpty
        else {
            // 결과 없음도 캐싱해 불필요한 재요청 방지 (Leaguepedia 서비스와 동일한 패턴)
            AppDiskCache.set(cacheKey, value: "")
            return nil
        }

        let urlString = "\(cdnBase)/players/\(photo)"
        AppDiskCache.set(cacheKey, value: urlString)
        return URL(string: urlString)
    }
}
