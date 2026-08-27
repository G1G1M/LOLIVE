//
//  FirebaseMatchDetailService.swift
//  LOLIVE
//

import Foundation
import FirebaseFunctions

/// 완료된 경기의 상세(밴픽·게임별 승자)를 서버(getMatchDetail Callable)에서 조회한다.
/// 서버는 경기가 끝나는 즉시 한 번만 Riot API를 불러 Firestore에 영구 저장해두므로,
/// 여기서 히트하면 Riot을 다시 호출할 필요가 없다. 없으면(백필 이전 경기 등) nil을
/// 반환해서 호출부가 기존처럼 Riot 직접 호출로 폴백하게 한다.
enum FirebaseMatchDetailService {
    static func fetchCachedDetail(matchId: String) async -> EventDetailInfo? {
        do {
            let functions = Functions.functions(region: "asia-northeast3")
            let result = try await functions.httpsCallable("getMatchDetail").call(["matchId": matchId])
            guard let dict = result.data as? [String: Any],
                  let detailDict = dict["detail"] as? [String: Any]
            else { return nil }
            let data = try JSONSerialization.data(withJSONObject: detailDict)
            return try JSONDecoder().decode(EventDetailInfo.self, from: data)
        } catch {
            return nil
        }
    }
}
