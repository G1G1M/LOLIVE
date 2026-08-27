import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - FirebaseService

@Observable
final class FirebaseService {
    static let shared = FirebaseService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "asia-northeast3")

    private init() {}

    // MARK: - 경기 일정 (실시간 구독)

    /// 오늘 경기 목록을 실시간으로 구독
    func listenToTodayMatches(onChange: @escaping ([Match]) -> Void) -> ListenerRegistration {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return db.collection("matches")
            .whereField("startTime", isGreaterThanOrEqualTo: ISO8601DateFormatter().string(from: startOfDay))
            .whereField("startTime", isLessThan: ISO8601DateFormatter().string(from: endOfDay))
            .order(by: "startTime")
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let matches = docs.compactMap { Match(from: $0.data()) }
                onChange(matches)
            }
    }

    /// 라이브 경기 목록을 실시간으로 구독
    func listenToLiveMatches(onChange: @escaping ([Match]) -> Void) -> ListenerRegistration {
        return db.collection("matches")
            .whereField("state", isEqualTo: "inProgress")
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents else { return }
                let matches = docs.compactMap { Match(from: $0.data()) }
                onChange(matches)
            }
    }

    /// 특정 경기 실시간 구독
    func listenToMatch(id: String, onChange: @escaping (Match?) -> Void) -> ListenerRegistration {
        return db.collection("matches").document(id)
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else {
                    onChange(nil)
                    return
                }
                onChange(Match(from: data))
            }
    }

    // MARK: - 게임 윈도우

    func listenToGameWindow(matchId: String, onChange: @escaping ([String: Any]?) -> Void) -> ListenerRegistration {
        return db.collection("gameWindows").document(matchId)
            .addSnapshotListener { snapshot, _ in
                onChange(snapshot?.data()?["data"] as? [String: Any])
            }
    }

    // MARK: - 선수 이미지 (Cloud Function)

    func fetchPlayerImageURL(summonerName: String) async -> URL? {
        do {
            let result = try await functions
                .httpsCallable("getPlayerImageURL")
                .call(["summonerName": summonerName])

            guard let data = result.data as? [String: Any],
                  let urlString = data["url"] as? String,
                  let url = URL(string: urlString)
            else { return nil }

            return url
        } catch {
            return nil
        }
    }

    // MARK: - 선수 스탯 (Cloud Function)

    func fetchPlayerStats(summonerName: String, tournament: String) async -> [[String: Any]] {
        do {
            let result = try await functions
                .httpsCallable("getPlayerStats")
                .call(["summonerName": summonerName, "tournament": tournament])

            return (result.data as? [String: Any])?["stats"] as? [[String: Any]] ?? []
        } catch {
            return []
        }
    }

    // MARK: - 일정 범위 조회 (one-shot)

    func fetchMatches(leagueId: String? = nil, limit: Int = 20) async -> [Match] {
        do {
            var query: Query = db.collection("matches")
                .whereField("startTime", isGreaterThanOrEqualTo: ISO8601DateFormatter().string(from: Date()))
                .order(by: "startTime")
                .limit(to: limit)

            if let leagueId {
                query = db.collection("matches")
                    .whereField("league.id", isEqualTo: leagueId)
                    .whereField("startTime", isGreaterThanOrEqualTo: ISO8601DateFormatter().string(from: Date()))
                    .order(by: "startTime")
                    .limit(to: limit)
            }

            let snapshot = try await query.getDocuments()
            return snapshot.documents.compactMap { Match(from: $0.data()) }
        } catch {
            return []
        }
    }
}

// MARK: - Match Firestore 디코딩

extension Match {
    init?(from data: [String: Any]) {
        guard
            let id = data["id"] as? String,
            let leagueData = data["league"] as? [String: Any],
            let teamAData = data["teamA"] as? [String: Any],
            let teamBData = data["teamB"] as? [String: Any],
            let startTimeStr = data["startTime"] as? String,
            let stateStr = data["state"] as? String,
            let state = MatchState(rawValue: stateStr)
        else { return nil }

        guard
            let league = League(from: leagueData),
            let teamA = Team(from: teamAData),
            let teamB = Team(from: teamBData)
        else { return nil }

        let formatter = ISO8601DateFormatter()
        let startTime = formatter.date(from: startTimeStr) ?? Date()

        self.init(
            id: id,
            league: league,
            teamA: teamA,
            teamB: teamB,
            scoreA: data["scoreA"] as? Int ?? 0,
            scoreB: data["scoreB"] as? Int ?? 0,
            startTime: startTime,
            state: state
        )
    }
}

extension League {
    init?(from data: [String: Any]) {
        guard
            let id = data["id"] as? String,
            let name = data["name"] as? String,
            let region = data["region"] as? String
        else { return nil }

        self.init(
            id: id,
            slug: data["slug"] as? String ?? "",
            name: name,
            region: region,
            imageURL: data["imageURL"] as? String
        )
    }
}

extension Team {
    init?(from data: [String: Any]) {
        guard
            let id = data["id"] as? String,
            let name = data["name"] as? String,
            let code = data["code"] as? String
        else { return nil }

        self.init(
            id: id,
            name: name,
            code: code,
            imageURL: data["imageURL"] as? String
        )
    }
}
