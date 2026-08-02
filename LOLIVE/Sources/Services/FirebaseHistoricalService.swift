//
//  FirebaseHistoricalService.swift
//  LOLIVE
//

import Foundation
import FirebaseFunctions

/// 2013년~ 과거 시즌(Worlds/MSI + 각 정규 리그) 기록을 서버(getHistoricalYears/
/// getHistoricalMatches Callable)에서 조회한다. 서버가 Leaguepedia를 미리 백필해둔
/// Firestore 데이터만 읽으므로, 앱은 Leaguepedia를 직접 호출하지 않는다.
enum FirebaseHistoricalService {
    private static let functions = Functions.functions(region: "asia-northeast3")

    static func fetchYears(leagueName: String) async -> [Int] {
        do {
            let result = try await functions.httpsCallable("getHistoricalYears").call(["leagueName": leagueName])
            guard let dict = result.data as? [String: Any] else { return [] }
            return (dict["years"] as? [Any])?.compactMap { $0 as? Int ?? ($0 as? NSNumber)?.intValue } ?? []
        } catch {
            return []
        }
    }

    static func fetchMatches(leagueName: String, year: Int) async -> [Match] {
        do {
            let result = try await functions.httpsCallable("getHistoricalMatches").call([
                "leagueName": leagueName, "year": year,
            ])
            guard let dict = result.data as? [String: Any],
                  let matchDicts = dict["matches"] as? [[String: Any]]
            else { return [] }
            let data = try JSONSerialization.data(withJSONObject: matchDicts)
            let decoder = JSONDecoder()
            // 서버가 Date.toISOString()으로 보내서 밀리초(.SSS)가 포함됨 — 기본 .iso8601
            // 전략(ISO8601DateFormatter, 밀리초 미지원)은 이걸 파싱 못 해 디코딩이 실패한다.
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let str = try container.decode(String.self)
                if let date = fractional.date(from: str) ?? plain.date(from: str) {
                    return date
                }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "잘못된 날짜 형식: \(str)")
            }
            return try decoder.decode([Match].self, from: data)
        } catch {
            return []
        }
    }
}
