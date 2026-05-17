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
    }

    private static let baseURL = "https://esports-api.lolesports.com/persisted/gw"
    private static let apiKey  = "0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z"

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
                liveMatch = NextMatchInfo(
                    opponentName: opponentName, opponentCode: opponentCode,
                    opponentImageURL: opponentImage, startTime: startTime, isLive: true
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
