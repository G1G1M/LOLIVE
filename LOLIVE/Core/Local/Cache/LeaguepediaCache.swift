//
//  LeaguepediaCache.swift
//  LOLIVE
//
//  Leaguepedia 데이터의 메모리 + 디스크 캐시 레이어.
//
//  [캐시 계층]
//  1. 메모리(actor 프로퍼티): 앱 세션 내 즉시 반환
//  2. 디스크(~/Caches/LeaguepediaStats/): 앱 재실행 후에도 유지
//
//  [TTL]
//  - 선수 스탯 / 챔피언픽 / OverviewPage: 24시간
//  - 과거 경기(Worlds/MSI): 30일 (완료 데이터는 거의 변경 없음)
//

import Foundation

// MARK: - Cache Actor

/// Leaguepedia API 응답 전체를 관리하는 캐시.
/// actor로 선언해 Swift 6 동시성 환경에서 데이터 레이스를 방지한다.
actor LeaguepediaCache {

    static let shared = LeaguepediaCache()

    // MARK: 메모리 캐시 (세션 내 유지)

    private var overviewPages:            [String: String]                          = [:]
    private var candidatePagesDic:        [String: [String]]                        = [:]
    private var playerNameSets:           [String: Set<String>]                     = [:]
    private var seasonStats:              [String: PlayerSeasonStats?]              = [:]
    private var allPlayerStatsDic:        [String: [String: PlayerSeasonStats]]     = [:]
    private var championPicksDic:         [String: [ChampionPickEntry]]             = [:]
    private var allChampionPicksBatchDic: [String: [String: [ChampionPickEntry]]]   = [:]
    private var historicalMatchesDic:     [String: [Match]]                         = [:]
    private var tournamentPagesDic:       [String: [LPTournamentEntry]]             = [:]

    // MARK: 디스크 캐시 디렉토리

    /// ~/Library/Caches/LeaguepediaStats/ — 앱 재실행 후에도 캐시 유지
    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeaguepediaStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let maxAge: TimeInterval          = 24 * 3600       // 스탯 캐시 TTL
    private static let historicalMaxAge: TimeInterval = 30 * 24 * 3600 // 과거 경기 TTL

    // MARK: - Init

    init() {
        let dir = Self.cacheDir
        if let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for file in files {
                let name = file.lastPathComponent
                // 구버전 hist_ 캐시 파일 삭제 (이미지 없는 형식)
                if name.hasPrefix("hist_") {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                // histv2_ 중 빈 파일 삭제 (파싱 실패로 생긴 빈 결과)
                if name.hasPrefix("histv2_"),
                   let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size < 200 {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        // OverviewPage 매핑은 앱 재실행 시 디스크에서 복원 (API 호출 없이 즉시 사용)
        if let data = try? Data(contentsOf: Self.overviewPagesDiskFile),
           let wrapper = try? JSONDecoder().decode(OverviewPagesDiskWrapper.self, from: data),
           Date().timeIntervalSince(wrapper.savedAt) < Self.maxAge {
            overviewPages = wrapper.pages
        }
    }

    // MARK: - OverviewPage

    func overviewPage(for leagueName: String) -> String? { overviewPages[leagueName] }

    func setOverviewPage(_ page: String, for leagueName: String) {
        overviewPages[leagueName] = page
        // 디스크에도 즉시 저장 — 앱 재실행 후 candidateOverviewPages API 호출 생략
        let wrapper = OverviewPagesDiskWrapper(savedAt: Date(), pages: overviewPages)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.overviewPagesDiskFile, options: .atomic)
        }
    }

    func candidatePages(for leagueName: String) -> [String]? { candidatePagesDic[leagueName] }
    func setCandidatePages(_ pages: [String], for leagueName: String) {
        candidatePagesDic[leagueName] = pages
    }

    // MARK: - 선수 이름

    func playerNames(for leagueName: String) -> Set<String>? {
        if let mem = playerNameSets[leagueName] { return mem }
        let file = Self.playerNamesFile(for: leagueName)
        guard let data = try? Data(contentsOf: file),
              let wrapper = try? JSONDecoder().decode(PlayerNamesDiskWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < Self.maxAge else { return nil }
        playerNameSets[leagueName] = wrapper.names
        return wrapper.names
    }

    func setPlayerNames(_ names: Set<String>, for leagueName: String) {
        playerNameSets[leagueName] = names
        let wrapper = PlayerNamesDiskWrapper(savedAt: Date(), names: names)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.playerNamesFile(for: leagueName), options: .atomic)
        }
    }

    // MARK: - 시즌 스탯 (개별 선수)

    /// nil?? → "조회한 적 있고 결과도 nil"과 "조회한 적 없음"을 구분하기 위해 Optional Optional 사용
    func cachedSeasonStats(key: String) -> PlayerSeasonStats?? { seasonStats[key] }
    func setSeasonStats(_ stats: PlayerSeasonStats?, key: String) { seasonStats[key] = .some(stats) }

    // MARK: - 시즌 스탯 (리그 전체 배치)

    /// 메모리 → 디스크 순으로 탐색. TTL 초과 시 nil 반환 → 재요청
    func allPlayerStats(for page: String) -> [String: PlayerSeasonStats]? {
        if let mem = allPlayerStatsDic[page] { return mem }
        let file = Self.cacheFile(for: page)
        guard let data = try? Data(contentsOf: file),
              let wrapper = try? JSONDecoder().decode(DiskWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < Self.maxAge else { return nil }
        allPlayerStatsDic[page] = wrapper.stats
        return wrapper.stats
    }

    func setAllPlayerStats(_ stats: [String: PlayerSeasonStats], for page: String) {
        allPlayerStatsDic[page] = stats
        let wrapper = DiskWrapper(savedAt: Date(), stats: stats)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.cacheFile(for: page), options: .atomic)
        }
    }

    // MARK: - 챔피언 픽 (개별 선수)

    func cachedChampionPicks(key: String) -> [ChampionPickEntry]? {
        if let mem = championPicksDic[key] { return mem }
        let file = Self.champCacheFile(for: key)
        guard let data = try? Data(contentsOf: file),
              let wrapper = try? JSONDecoder().decode(ChampPicksDiskWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < Self.maxAge else { return nil }
        championPicksDic[key] = wrapper.picks
        return wrapper.picks
    }

    func setChampionPicks(_ picks: [ChampionPickEntry], key: String) {
        championPicksDic[key] = picks
        let wrapper = ChampPicksDiskWrapper(savedAt: Date(), picks: picks)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.champCacheFile(for: key), options: .atomic)
        }
    }

    // MARK: - 챔피언 픽 (리그 전체 배치)

    func allChampionPicksBatch(for page: String) -> [String: [ChampionPickEntry]]? {
        if let mem = allChampionPicksBatchDic[page] { return mem }
        let file = Self.champBatchFile(for: page)
        guard let data = try? Data(contentsOf: file),
              let wrapper = try? JSONDecoder().decode(ChampBatchDiskWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < Self.maxAge else { return nil }
        allChampionPicksBatchDic[page] = wrapper.picks
        return wrapper.picks
    }

    func setAllChampionPicksBatch(_ picks: [String: [ChampionPickEntry]], for page: String) {
        allChampionPicksBatchDic[page] = picks
        let wrapper = ChampBatchDiskWrapper(savedAt: Date(), picks: picks)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.champBatchFile(for: page), options: .atomic)
        }
    }

    // MARK: - 과거 경기 (30일 TTL)

    func cachedHistoricalMatches(key: String) -> [Match]? {
        if let mem = historicalMatchesDic[key] { return mem }
        let file = Self.historicalFile(for: key)
        guard let data = try? Data(contentsOf: file),
              let wrapper = try? JSONDecoder().decode(HistMatchesWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < Self.historicalMaxAge else { return nil }
        historicalMatchesDic[key] = wrapper.matches
        return wrapper.matches
    }

    func setHistoricalMatches(_ matches: [Match], key: String) {
        historicalMatchesDic[key] = matches
        // 빈 배열은 디스크에 저장하지 않음 — 파싱 실패로 인한 빈 결과가 영구 캐시되는 것 방지
        guard !matches.isEmpty else { return }
        let wrapper = HistMatchesWrapper(savedAt: Date(), matches: matches)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.historicalFile(for: key), options: .atomic)
        }
    }

    // MARK: - 대회 페이지 목록

    func cachedTournamentPages(key: String) -> [LPTournamentEntry]? {
        if let mem = tournamentPagesDic[key] { return mem }
        let file = Self.tournamentPagesFile(for: key)
        guard let data = try? Data(contentsOf: file),
              let wrapper = try? JSONDecoder().decode(TournamentPagesWrapper.self, from: data),
              Date().timeIntervalSince(wrapper.savedAt) < Self.maxAge else { return nil }
        tournamentPagesDic[key] = wrapper.entries
        return wrapper.entries
    }

    func setTournamentPages(_ entries: [LPTournamentEntry], key: String) {
        tournamentPagesDic[key] = entries
        let wrapper = TournamentPagesWrapper(savedAt: Date(), entries: entries)
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: Self.tournamentPagesFile(for: key), options: .atomic)
        }
    }

    // MARK: - 디스크 파일 경로 헬퍼

    private static let overviewPagesDiskFile =
        cacheDir.appendingPathComponent("overview_pages.json")

    private static func cacheFile(for page: String) -> URL {
        let safe = page.replacingOccurrences(of: "/", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }

    private static func champCacheFile(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("champs_\(safe).json")
    }

    private static func champBatchFile(for page: String) -> URL {
        let safe = page
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("champ_batch_\(safe).json")
    }

    private static func playerNamesFile(for leagueName: String) -> URL {
        let safe = leagueName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("playernames_\(safe).json")
    }

    private static func historicalFile(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }

    private static func tournamentPagesFile(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cacheDir.appendingPathComponent("ovpages_\(safe).json")
    }

    // MARK: - 디스크 래퍼 타입 (Codable 직렬화용)

    private struct DiskWrapper: Codable {
        let savedAt: Date
        let stats: [String: PlayerSeasonStats]
    }

    private struct ChampPicksDiskWrapper: Codable {
        let savedAt: Date
        let picks: [ChampionPickEntry]
    }

    private struct ChampBatchDiskWrapper: Codable {
        let savedAt: Date
        let picks: [String: [ChampionPickEntry]]
    }

    private struct HistMatchesWrapper: Codable {
        let savedAt: Date
        let matches: [Match]
    }

    private struct TournamentPagesWrapper: Codable {
        let savedAt: Date
        let entries: [LPTournamentEntry]
    }

    private struct PlayerNamesDiskWrapper: Codable {
        let savedAt: Date
        let names: Set<String>
    }

    private struct OverviewPagesDiskWrapper: Codable {
        let savedAt: Date
        let pages: [String: String]
    }
}
