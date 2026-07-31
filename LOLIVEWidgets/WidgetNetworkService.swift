//
//  WidgetNetworkService.swift
//  LOLIVEWidgets
//
//  위젯 Extension 전용 최소 Riot API 클라이언트
//

import Foundation

enum WidgetNetworkService {

    struct NextMatchInfo: Sendable {
        let opponentName: String
        let opponentCode: String
        let opponentImageURL: String?
        let startTime: Date
        let isLive: Bool
        var myScore: Int? = nil
        var oppScore: Int? = nil
        var currentGame: Int? = nil
    }

    private static let baseURL = "https://esports-api.lolesports.com/persisted/gw"
    private static let apiKey  = APIKeys.riotApiKey

    static func fetchNextMatch(leagueId: String, teamCode: String) async -> NextMatchInfo? {
        var components = URLComponents(string: baseURL + "/getSchedule")
        components?.queryItems = [
            URLQueryItem(name: "hl", value: "ko-KR"),
            URLQueryItem(name: "leagueId", value: leagueId)
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return parse(data: data, teamCode: teamCode)
    }

    // MARK: - Private

    // MARK: - Live Match Detection

    /// 현재 진행 중인 모든 경기를 teamCode(대문자) → NextMatchInfo 딕셔너리로 반환
    /// condition == false 이면 네트워크 호출 없이 빈 딕셔너리 즉시 반환
    ///
    /// 메인 앱이 90초 이내에 App Group에 저장해둔 라이브 스냅샷이 있으면 그걸 그대로 재사용하고
    /// 네트워크 호출을 건너뛴다 — 앱이 실행 중(30초마다 갱신)일 땐 위젯이 굳이 자체 API를 또 부를 필요가 없다.
    /// 스냅샷이 없거나 오래됐으면(앱이 백그라운드/종료 상태) 기존처럼 직접 호출한다.
    static func fetchAllLiveMatchInfo(onlyIf condition: Bool = true) async -> [String: NextMatchInfo] {
        guard condition else { return [:] }

        let shared = SharedDataService.loadAllNextMatches()
        let isSnapshotFresh = shared.values.contains { Date().timeIntervalSince($0.savedAt) < 90 }
        if isSnapshotFresh {
            return shared.filter { $0.value.isLive }.mapValues {
                NextMatchInfo(
                    opponentName: $0.opponentName,
                    opponentCode: $0.opponentCode,
                    opponentImageURL: $0.opponentImageURL,
                    startTime: $0.startTime,
                    isLive: true,
                    myScore: $0.myScore,
                    oppScore: $0.oppScore,
                    currentGame: $0.currentGame
                )
            }
        }

        var components = URLComponents(string: baseURL + "/getLive")
        components?.queryItems = [URLQueryItem(name: "hl", value: "ko-KR")]
        guard let url = components?.url else { return [:] }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [:] }
        return parseAllLive(data: data)
    }

    private static func parseAllLive(data: Data) -> [String: NextMatchInfo] {
        guard
            let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj  = json["data"]        as? [String: Any],
            let schedule = dataObj["schedule"] as? [String: Any],
            let events   = schedule["events"]  as? [[String: Any]]
        else { return [:] }

        var result: [String: NextMatchInfo] = [:]
        let iso = ISO8601DateFormatter()

        for event in events {
            guard
                let matchDict = event["match"]     as? [String: Any],
                let teams     = matchDict["teams"] as? [[String: Any]],
                teams.count >= 2
            else { continue }

            let startTime = (event["startTime"] as? String).flatMap { iso.date(from: $0) } ?? Date()
            let games = matchDict["games"] as? [[String: Any]] ?? []
            let currentGame = games.filter { ($0["state"] as? String) == "completed" }.count + 1
            let scores = teams.map { ($0["result"] as? [String: Any])?["gameWins"] as? Int ?? 0 }

            for i in 0..<2 {
                guard let code = teams[i]["code"] as? String else { continue }
                let opp = teams[1 - i]
                result[code.uppercased()] = NextMatchInfo(
                    opponentName:     (opp["name"]  as? String) ?? "TBD",
                    opponentCode:     (opp["code"]  as? String) ?? "TBD",
                    opponentImageURL: (opp["image"] as? String)?.replacingOccurrences(of: "http://", with: "https://"),
                    startTime:        startTime,
                    isLive:           true,
                    myScore:          scores[i],
                    oppScore:         scores[1 - i],
                    currentGame:      currentGame
                )
            }
        }
        return result
    }

    // MARK: - Schedule Parse

    private static func parse(data: Data, teamCode: String) -> NextMatchInfo? {
        guard
            let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj  = json["data"]     as? [String: Any],
            let schedule = dataObj["schedule"] as? [String: Any],
            let events   = schedule["events"]  as? [[String: Any]]
        else { return nil }

        let iso = ISO8601DateFormatter()
        let now = Date()

        // inProgress 경기 우선 → 없으면 가장 가까운 unstarted
        var liveMatch: NextMatchInfo?
        var nextMatch: NextMatchInfo?

        for event in events {
            guard
                let state     = event["state"]     as? String,
                let startStr  = event["startTime"] as? String,
                let startTime = iso.date(from: startStr),
                let matchDict = event["match"]     as? [String: Any],
                let teams     = matchDict["teams"] as? [[String: Any]],
                teams.count >= 2
            else { continue }

            let codes = teams.compactMap { $0["code"] as? String }
            guard codes.contains(where: { $0.lowercased() == teamCode.lowercased() }) else { continue }

            let opponentDict = teams.first { ($0["code"] as? String)?.lowercased() != teamCode.lowercased() }
            let opponentName  = (opponentDict?["name"]  as? String) ?? "TBD"
            let opponentCode  = (opponentDict?["code"]  as? String) ?? "TBD"
            let opponentImage = (opponentDict?["image"] as? String)?
                .replacingOccurrences(of: "http://", with: "https://")

            if state == "inProgress" && liveMatch == nil {
                let myDict = teams.first { ($0["code"] as? String)?.lowercased() == teamCode.lowercased() }
                let myScore  = (myDict?["result"] as? [String: Any])?["gameWins"] as? Int ?? 0
                let oppScore = (opponentDict?["result"] as? [String: Any])?["gameWins"] as? Int ?? 0
                let games = matchDict["games"] as? [[String: Any]] ?? []
                let currentGame = games.filter { ($0["state"] as? String) == "completed" }.count + 1
                liveMatch = NextMatchInfo(
                    opponentName: opponentName, opponentCode: opponentCode,
                    opponentImageURL: opponentImage, startTime: startTime, isLive: true,
                    myScore: myScore, oppScore: oppScore, currentGame: currentGame
                )
            } else if state == "unstarted" && startTime > now && nextMatch == nil {
                nextMatch = NextMatchInfo(
                    opponentName: opponentName, opponentCode: opponentCode,
                    opponentImageURL: opponentImage, startTime: startTime, isLive: false
                )
            }

            if liveMatch != nil && nextMatch != nil { break }
        }

        return liveMatch ?? nextMatch
    }
}
