//
//  Match.swift
//  LOLIVE
//

import Foundation

enum MatchState: String, Codable, Hashable {
    case unstarted
    case inProgress
    case completed
}

struct Match: Codable, Identifiable, Hashable {
    let id: String
    let league: League
    let teamA: Team
    let teamB: Team
    let scoreA: Int
    let scoreB: Int
    let startTime: Date
    let state: MatchState
    let blockName: String?  // "Week 1", "Playoffs", "Road to MSI" 등
    let games: [BackfilledGameDetail]?  // 과거 시즌 백필 경기에만 존재(oe.datalisk.io 게임별 상세)
    /// 과거 시즌 백필 데이터에만 있는 "시즌 구간" 식별자(예: "LCK/2026 Season/Rounds 3-4").
    /// 매일 자동 동기화되는 최신 데이터는 "live-sync" 고정값, 그 외 일반 경기 데이터엔 없음(nil).
    let overviewPage: String?

    init(id: String, league: League, teamA: Team, teamB: Team,
         scoreA: Int, scoreB: Int, startTime: Date, state: MatchState,
         blockName: String? = nil, games: [BackfilledGameDetail]? = nil, overviewPage: String? = nil) {
        self.id = id
        self.league = league
        self.teamA = teamA
        self.teamB = teamB
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.startTime = startTime
        self.state = state
        self.blockName = blockName
        self.games = games
        self.overviewPage = overviewPage
    }

    /// 같은 라운드를 하나로 묶은 그룹 — `label`은 그 라운드에서 가장 많이 쓰인 blockName 표기
    /// (필요할 때만 시즌 구간 이름이 앞에 붙는다. 예: "Rounds 1-2 · Week 1").
    struct RoundGroup: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let matches: [Match]
    }

    /// blockName이 언어에 따라 다르게 들어올 수 있어서("8강" vs "Quarterfinals") 그대로 쓰면
    /// 같은 라운드가 칩 두 개로 중복 표시된다 — 실측 확인(historicalMatches엔 Oracle's Elixir 백필
    /// 원본(영어)과 Riot API `hl=ko-KR` 기반 syncHistoricalDaily 복사본(한국어)이 섞여 있음).
    /// 번호 없는 상위 카테고리 라운드명만 알려진 한/영 쌍으로 병합한다 — "Round 3"/"Bracket Round 2"
    /// 처럼 번호가 붙은 세부 라운드는 실제로 서로 다른 라운드라(실측: MSI Bracket Round 1~4 전부
    /// 별개 경기) 병합하면 안 되고, 이런 값은 전부 영어로만 나와서 애초에 언어 중복이 없다.
    private static let roundCanonicalKeys: [String: String] = [
        "결승": "finals", "finals": "finals", "그랜드 파이널": "grand final", "grand final": "grand final",
        "4강": "semifinals", "semifinals": "semifinals",
        "8강": "quarterfinals", "quarterfinals": "quarterfinals",
        "16강": "round of 16", "round of 16": "round of 16",
        "플레이-인": "play-in", "플레이인": "play-in", "play-in": "play-in",
        "스위스": "swiss stage", "swiss stage": "swiss stage", "swiss": "swiss stage",
        "그룹 스테이지": "group stage", "group stage": "group stage",
        "토너먼트 스테이지": "bracket stage", "bracket stage": "bracket stage",
    ]

    /// 백필 데이터의 overviewPage("LCK/2026 Season/Rounds 3-4")에서 사람이 읽는 구간 이름만
    /// 뽑아낸다("Rounds 3-4"). 매일 동기화 데이터("live-sync")는 구간 구분이 없어 빈 문자열.
    private static func splitLabel(_ overviewPage: String?) -> String {
        guard let overviewPage, overviewPage != "live-sync" else { return "" }
        return overviewPage.split(separator: "/").last.map(String.init) ?? overviewPage
    }

    /// 한 해 안에도 컵/정규시즌/플레이오프처럼 시즌 구간이 여러 개 있는 리그가 있고, 그 구간마다
    /// "Week 1", "Round 1", "Finals" 같은 라운드 이름이 그대로 반복된다(실측 확인: LCK 2025년에
    /// "Round 1"이 Road to MSI/Season Play-In/Season Playoffs 세 구간에 각각 존재). blockName만
    /// 보고 묶으면 서로 다른 구간의 라운드가 하나로 합쳐져버리기도 하고, 안 합쳐지더라도 "이게
    /// 어느 구간 라운드인지" 알 수 없어 혼란스럽다(예: 시즌이 안 끝났는데 "Finals"만 덩그러니
    /// 보이는 문제 — 실제로는 이미 끝난 컵 대회의 결승이었음). 그래서 백필 데이터는 시즌 구간
    /// 이름을 항상 라벨 앞에 붙인다. 순서는 라운드 이름을 추측하는 대신 그 라운드에 속한 가장
    /// 최근 경기 날짜 기준으로 정렬한다 — "Week 1~15"처럼 번호가 있는 라운드도 이름 패턴 없이
    /// 자동으로 올바른 순서가 됨.
    static func roundGroups(from matches: [Match]) -> [RoundGroup] {
        struct GroupKey: Hashable { let split: String; let canonical: String }

        let named = matches.compactMap { m -> (canonical: String, rawName: String, match: Match)? in
            guard let name = m.blockName else { return nil }
            return (roundCanonicalKeys[name.lowercased()] ?? name.lowercased(), name, m)
        }

        var buckets: [GroupKey: [Match]] = [:]
        var labelVotes: [GroupKey: [String: Int]] = [:]  // 라벨 후보별 등장 횟수(더 흔한 표기 채택)
        for (canonical, rawName, m) in named {
            let key = GroupKey(split: splitLabel(m.overviewPage), canonical: canonical)
            buckets[key, default: []].append(m)
            labelVotes[key, default: [:]][rawName, default: 0] += 1
        }

        let groups = buckets.map { key, ms -> RoundGroup in
            let commonName = labelVotes[key]?.max { $0.value < $1.value }?.key ?? key.canonical
            let label = key.split.isEmpty ? commonName : "\(key.split) · \(commonName)"
            return RoundGroup(label: label, matches: ms)
        }

        return groups.sorted { g0, g1 in
            (g0.matches.map(\.startTime).max() ?? .distantPast) >
            (g1.matches.map(\.startTime).max() ?? .distantPast)
        }
    }

    /// 같은 실제 경기가 서로 다른 소스로 중복 저장된 경우 하나만 남긴다. 매일 자동 동기화되는
    /// "live-sync" 임시 기록이 나중에 정식 백필로 대체되는데, 팀 표기 방식이 소스마다 달라서
    /// (백필 쪽은 "Hanwha Life Esports" 같은 전체 이름, live-sync 쪽은 "HLE" 같은 짧은 코드)
    /// 팀 이름으로 같은 경기인지 비교하는 건 신뢰할 수 없다(실측: 앞 3글자 비교로는
    /// "han"(Hanwha) vs "hle"(HLE)처럼 아예 안 맞는 경우가 있었음). 대신 "이 날짜에 정식 백필
    /// 데이터가 하나라도 있으면 그 날짜의 live-sync 기록은 전부 버린다"는 규칙을 쓴다 — 리그당
    /// 하루에 경기가 1~2개뿐이라 날짜 단위로도 충분히 안전하고, 팀 이름 매칭이 필요 없다.
    static func deduplicatedAcrossSources(_ matches: [Match]) -> [Match] {
        let cal = Calendar.current
        let officialDays = Set(matches.compactMap { m -> TimeInterval? in
            guard let overviewPage = m.overviewPage, overviewPage != "live-sync" else { return nil }
            return cal.startOfDay(for: m.startTime).timeIntervalSince1970
        })
        return matches.filter { m in
            guard m.overviewPage == "live-sync" else { return true }
            return !officialDays.contains(cal.startOfDay(for: m.startTime).timeIntervalSince1970)
        }
    }
}

/// 백필된 과거 시즌 경기(datalisk.io) 한 게임(세트)의 상세 정보 — 밴 데이터는 없음(원본에 없음).
struct BackfilledGameDetail: Codable, Hashable {
    let number: Int
    let gameId: String
    let patch: Double?
    let vod: String?
    let blueTeamId: String
    let redTeamId: String
    let winnerTeamId: String?
    let blueTeamStats: TeamGameStats
    let redTeamStats: TeamGameStats
    let bluePlayers: [PlayerStats]
    let redPlayers: [PlayerStats]
}
