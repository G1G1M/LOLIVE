//
//  FavoriteTeamWidget.swift
//  LOLIVEWidgets
//

import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Navigate Intent (캐러셀)

struct NavigateTeamIntent: AppIntent {
    static var title: LocalizedStringResource = "팀 이동"
    static var isDiscoverable: Bool = false

    @Parameter(title: "인덱스")
    var newIndex: Int

    init() { newIndex = 0 }
    init(newIndex: Int) { self.newIndex = newIndex }

    func perform() async throws -> some IntentResult {
        SharedDataService.saveCurrentTeamIndex(newIndex)
        WidgetCenter.shared.reloadTimelines(ofKind: "FavoriteTeamWidget")
        return .result()
    }
}

// MARK: - Team Row Info (Large 위젯용)

struct TeamRowInfo: Sendable {
    let teamCode: String
    let teamName: String
    let leagueName: String
    let teamImageData: Data?
    let nextMatch: WidgetNetworkService.NextMatchInfo?
    let opponentImageData: Data?
}

// MARK: - Entry

struct FavoriteTeamEntry: TimelineEntry {
    let date: Date
    // 현재 선택 팀 (Small / Medium)
    let teamId: String
    let teamName: String
    let teamCode: String
    let teamImageData: Data?
    let leagueName: String
    let nextMatch: WidgetNetworkService.NextMatchInfo?
    let opponentImageData: Data?
    let currentIndex: Int
    let totalTeams: Int
    let isConfigured: Bool
    // 전체 팀 목록 (Large)
    let allTeams: [TeamRowInfo]

    static let placeholder: FavoriteTeamEntry = {
        let sampleMatch = WidgetNetworkService.NextMatchInfo(
            opponentName: "Gen.G",
            opponentCode: "GEN",
            opponentImageURL: nil,
            startTime: .now.addingTimeInterval(1800),
            isLive: false
        )
        let row1 = TeamRowInfo(teamCode: "T1",  teamName: "T1",    leagueName: "LCK", teamImageData: nil, nextMatch: sampleMatch, opponentImageData: nil)
        let row2 = TeamRowInfo(teamCode: "GEN", teamName: "Gen.G", leagueName: "LCK", teamImageData: nil, nextMatch: nil,         opponentImageData: nil)
        let row3 = TeamRowInfo(teamCode: "DRX", teamName: "DRX",   leagueName: "LCK", teamImageData: nil, nextMatch: nil,         opponentImageData: nil)
        return FavoriteTeamEntry(
            date: .now, teamId: "t1", teamName: "T1", teamCode: "T1",
            teamImageData: nil, leagueName: "LCK", nextMatch: sampleMatch,
            opponentImageData: nil, currentIndex: 0, totalTeams: 3, isConfigured: true,
            allTeams: [row1, row2, row3]
        )
    }()
}

// MARK: - Provider

struct FavoriteTeamProvider: TimelineProvider {

    func placeholder(in context: Context) -> FavoriteTeamEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (FavoriteTeamEntry) -> Void) {
        Task { completion(await buildEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoriteTeamEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            let nextUpdate: Date
            if let match = entry.nextMatch {
                if match.isLive {
                    // 라이브 중: 15분마다 종료 감지
                    nextUpdate = .now.addingTimeInterval(900)
                } else {
                    let timeToMatch = match.startTime.timeIntervalSinceNow
                    if timeToMatch > 5400 {
                        // 예정 1.5시간 이상 전: 라이브 체크 시작 시점에 갱신
                        nextUpdate = match.startTime.addingTimeInterval(-5400)
                    } else {
                        // 1.5시간 이내 또는 이미 지남: 5분마다 (일찍 시작 즉시 감지)
                        nextUpdate = .now.addingTimeInterval(300)
                    }
                }
            } else {
                nextUpdate = .now.addingTimeInterval(3600)
            }
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    // MARK: - Private

    private func buildEntry() async -> FavoriteTeamEntry {
        let teams = SharedDataService.loadFavoriteTeams()
        guard !teams.isEmpty else {
            return FavoriteTeamEntry(
                date: .now, teamId: "", teamName: "", teamCode: "",
                teamImageData: nil, leagueName: "", nextMatch: nil,
                opponentImageData: nil, currentIndex: 0, totalTeams: 0, isConfigured: false,
                allTeams: []
            )
        }

        var idx = SharedDataService.loadCurrentTeamIndex()
        idx = max(0, min(idx, teams.count - 1))
        let fav = teams[idx]

        // 전체 팀의 sharedMatch를 미리 로드 (Large 위젯과 공유)
        let allSharedMatches: [String: SharedNextMatch] = Dictionary(
            uniqueKeysWithValues: teams.compactMap { t -> (String, SharedNextMatch)? in
                guard let m = SharedDataService.loadNextMatch(teamCode: t.teamCode) else { return nil }
                return (t.teamCode.uppercased(), m)
            }
        )
        let currentSharedMatch = allSharedMatches[fav.teamCode.uppercased()]

        // sharedMatch 없는 팀이 있거나, 예정 1.5시간 이내인 팀이 있으면 라이브 API 1회 호출
        let noSharedData = teams.contains { allSharedMatches[$0.teamCode.uppercased()] == nil }
        let needsLiveCheck = noSharedData || allSharedMatches.values.contains {
            !$0.isLive && $0.startTime.timeIntervalSinceNow < 5400
        }

        async let liveInfoTask = WidgetNetworkService.fetchAllLiveMatchInfo(onlyIf: needsLiveCheck)
        async let apiMatchTask: WidgetNetworkService.NextMatchInfo? = currentSharedMatch == nil
            ? WidgetNetworkService.fetchNextMatch(leagueId: fav.leagueId, teamCode: fav.teamCode)
            : nil
        async let teamImgTask = fetchImageData(fav.teamImageURL)
        let (liveInfo, apiMatch, teamImg) = await (liveInfoTask, apiMatchTask, teamImgTask)

        // 우선순위: 라이브 API 확인 > App Group 데이터 > 스케줄 API fallback
        // sharedMatch 없을 때도 liveInfo 활용 (MSI 등 홈 리그 외 경기 커버)
        let shouldCheckLive = currentSharedMatch == nil || (currentSharedMatch.map {
            !$0.isLive && $0.startTime.timeIntervalSinceNow < 5400
        } ?? false)
        let liveCheck = shouldCheckLive ? liveInfo[fav.teamCode.uppercased()] : nil
        let match = liveCheck ?? currentSharedMatch.map {
            WidgetNetworkService.NextMatchInfo(
                opponentName: $0.opponentName,
                opponentCode: $0.opponentCode,
                opponentImageURL: $0.opponentImageURL,
                startTime: $0.startTime,
                isLive: $0.isLive
            )
        } ?? apiMatch

        let oppImg = await fetchImageData(match?.opponentImageURL)
                   ?? SharedDataService.loadTeamImageData(teamCode: match?.opponentCode ?? "")

        let allTeamsData = await loadAllTeams(teams, liveInfo: liveInfo, sharedMatches: allSharedMatches)
        let leagueName = currentSharedMatch?.leagueName ?? fav.leagueName

        return FavoriteTeamEntry(
            date: .now,
            teamId: fav.teamId,
            teamName: fav.teamName,
            teamCode: fav.teamCode,
            teamImageData: teamImg,
            leagueName: leagueName,
            nextMatch: match,
            opponentImageData: oppImg,
            currentIndex: idx,
            totalTeams: teams.count,
            isConfigured: true,
            allTeams: allTeamsData
        )
    }

    private func loadAllTeams(
        _ teams: [SharedFavoriteTeam],
        liveInfo: [String: WidgetNetworkService.NextMatchInfo],
        sharedMatches: [String: SharedNextMatch]
    ) async -> [TeamRowInfo] {
        await withTaskGroup(of: (Int, TeamRowInfo).self) { group in
            for (i, fav) in teams.enumerated() {
                let sharedMatch = sharedMatches[fav.teamCode.uppercased()]
                let shouldCheckLive = sharedMatch == nil || (sharedMatch.map {
                    !$0.isLive && $0.startTime.timeIntervalSinceNow < 5400
                } ?? false)
                let liveCheck = shouldCheckLive ? liveInfo[fav.teamCode.uppercased()] : nil

                group.addTask {
                    async let apiMatchTask: WidgetNetworkService.NextMatchInfo? = (sharedMatch == nil)
                        ? WidgetNetworkService.fetchNextMatch(leagueId: fav.leagueId, teamCode: fav.teamCode)
                        : nil
                    async let img = fetchImageData(fav.teamImageURL)
                    let (apiMatch, teamImg) = await (apiMatchTask, img)

                    let match = liveCheck ?? sharedMatch.map {
                        WidgetNetworkService.NextMatchInfo(
                            opponentName: $0.opponentName,
                            opponentCode: $0.opponentCode,
                            opponentImageURL: $0.opponentImageURL,
                            startTime: $0.startTime,
                            isLive: $0.isLive
                        )
                    } ?? apiMatch

                    let oppImg = await fetchImageData(match?.opponentImageURL)
                               ?? SharedDataService.loadTeamImageData(teamCode: match?.opponentCode ?? "")
                    let leagueName = sharedMatch?.leagueName ?? fav.leagueName
                    return (i, TeamRowInfo(
                        teamCode: fav.teamCode,
                        teamName: fav.teamName,
                        leagueName: leagueName,
                        teamImageData: teamImg,
                        nextMatch: match,
                        opponentImageData: oppImg
                    ))
                }
            }
            var results: [(Int, TeamRowInfo)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private func fetchImageData(_ urlString: String?) async -> Data? {
        guard let str = urlString, let url = URL(string: str) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }
}

// MARK: - Widget

struct FavoriteTeamWidget: Widget {
    let kind = "FavoriteTeamWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FavoriteTeamProvider()) { entry in
            FavoriteTeamWidgetView(entry: entry)
                .containerBackground(.fill, for: .widget)
        }
        .configurationDisplayName("즐겨찾기 팀")
        .description("즐겨찾기한 팀의 다음 경기 일정을 표시합니다.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// MARK: - Root View

struct FavoriteTeamWidgetView: View {
    let entry: FavoriteTeamEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if !entry.isConfigured {
                unconfiguredView
            } else if family == .systemLarge {
                largeView
            } else if family == .systemMedium {
                mediumView
            } else if family == .accessoryCircular {
                accessoryCircularView
            } else if family == .accessoryRectangular {
                accessoryRectangularView
            } else if family == .accessoryInline {
                accessoryInlineView
            } else {
                smallView
            }
        }
        .widgetURL(URL(string: "lolive://match/\(entry.teamCode.uppercased())"))
    }

    // MARK: - Accessory (잠금화면)

    /// 원형: 팀 로고 + 팀 코드
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let data = entry.teamImageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .padding(6)
            } else {
                Text(entry.teamCode)
                    .font(.caption2).fontWeight(.bold)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    /// 직사각형: 팀 vs 상대 + 경기 시간
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(entry.teamCode)
                    .font(.caption).fontWeight(.bold)
                if let match = entry.nextMatch {
                    Text("vs \(match.opponentCode)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            if let match = entry.nextMatch {
                if match.isLive {
                    Text("● LIVE")
                        .font(.caption2).fontWeight(.semibold)
                } else {
                    let timeToMatch = match.startTime.timeIntervalSinceNow
                    if timeToMatch > 0, timeToMatch <= 3600 {
                        Text(match.startTime, style: .timer)
                            .font(.caption2).fontWeight(.semibold)
                            .monospacedDigit().lineLimit(1)
                    } else {
                        Text(accessoryTimeText(match.startTime))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("경기 없음")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Text(entry.leagueName)
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 인라인 (잠금화면 시계 위/아래 한 줄)
    private var accessoryInlineView: some View {
        Group {
            if let match = entry.nextMatch {
                if match.isLive {
                    Text("\(entry.teamCode) vs \(match.opponentCode) · LIVE")
                } else {
                    let timeToMatch = match.startTime.timeIntervalSinceNow
                    if timeToMatch > 0, timeToMatch <= 3600 {
                        Text("\(entry.teamCode) vs \(match.opponentCode) · ") +
                        Text(match.startTime, style: .timer)
                    } else {
                        Text("\(entry.teamCode) vs \(match.opponentCode) · \(accessoryTimeText(match.startTime))")
                    }
                }
            } else {
                Text("\(entry.teamCode) · 예정된 경기 없음")
            }
        }
        .lineLimit(1)
    }

    private func accessoryTimeText(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date)    { return "오늘 \(time)" }
        if cal.isDateInTomorrow(date) { return "내일 \(time)" }
        return date.formatted(.dateTime.month().day()) + " \(time)"
    }

    // MARK: - Unconfigured

    private var unconfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.slash")
                .font(.title2).foregroundStyle(.secondary)
            Text("즐겨찾기한 팀이 없습니다")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                teamLogo(data: entry.teamImageData, size: 48)
                Text(entry.teamCode)
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                Text(entry.leagueName)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)

            if let match = entry.nextMatch {
                VStack(spacing: 5) {
                    if match.isLive {
                        liveBadge
                    } else {
                        Text("다음 경기").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        teamLogo(data: entry.opponentImageData, size: 18)
                        Text("vs \(match.opponentCode)")
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    matchTimeView(match: match, compact: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("예정된 경기 없음")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if entry.totalTeams > 1 {
                Spacer(minLength: 10)
                carouselDots
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium

    private var mediumView: some View {
        VStack(spacing: 0) {
            if let match = entry.nextMatch {
                HStack(spacing: 0) {
                    VStack(spacing: 5) {
                        teamLogo(data: entry.teamImageData, size: 44)
                        Text(entry.teamCode)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        if match.isLive {
                            liveBadge
                            Text("경기 진행 중")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            matchTimeView(match: match, compact: false)
                        }
                        Text(entry.leagueName)
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .frame(width: 110)

                    VStack(spacing: 5) {
                        teamLogo(data: entry.opponentImageData, size: 44)
                        Text(match.opponentCode)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 14) {
                    teamLogo(data: entry.teamImageData, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.teamCode)
                            .font(.title3).fontWeight(.bold).foregroundStyle(.primary)
                        Text(entry.leagueName)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("예정된 경기 없음")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }

            if entry.totalTeams > 1 {
                Spacer(minLength: 12)
                carouselControls
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Large (모든 팀 목록)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("즐겨찾기")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Text("즐겨찾기 팀")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)

            ForEach(Array(entry.allTeams.prefix(5).enumerated()), id: \.offset) { i, info in
                if i > 0 {
                    Divider().padding(.leading, 60)
                }
                largeTeamRow(info)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func largeTeamRow(_ info: TeamRowInfo) -> some View {
        HStack(spacing: 12) {
            teamLogo(data: info.teamImageData, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.teamCode)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.primary)
                Text(info.leagueName)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if let match = info.nextMatch {
                if match.isLive {
                    VStack(alignment: .trailing, spacing: 2) {
                        liveBadge
                        Text("vs \(match.opponentCode)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("vs \(match.opponentCode)")
                            .font(.caption2).fontWeight(.medium).foregroundStyle(.primary)
                        largeMatchTimeView(match: match)
                    }
                }
                teamLogo(data: info.opponentImageData, size: 28)
            } else {
                Text("경기 없음")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - Time Views

    @ViewBuilder
    private func matchTimeView(match: WidgetNetworkService.NextMatchInfo, compact: Bool) -> some View {
        let timeToMatch = match.startTime.timeIntervalSinceNow
        if !match.isLive, timeToMatch > 0, timeToMatch <= 3600 {
            // 1시간 이내: 라이브 카운트다운
            Text(match.startTime, style: .timer)
                .font(compact ? .caption2 : .title3)
                .fontWeight(.bold)
                .foregroundStyle(.orange)
                .monospacedDigit()
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if compact {
            Text(timeText(match.startTime, isLive: match.isLive))
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 2) {
                Text(timeOnly(match.startTime))
                    .font(.title3).fontWeight(.bold).foregroundStyle(.primary)
                Text(dateText(match.startTime))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func largeMatchTimeView(match: WidgetNetworkService.NextMatchInfo) -> some View {
        let timeToMatch = match.startTime.timeIntervalSinceNow
        if timeToMatch > 0, timeToMatch <= 3600 {
            Text(match.startTime, style: .timer)
                .font(.caption2).fontWeight(.semibold).foregroundStyle(.orange)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .trailing)
        } else {
            Text(timeText(match.startTime, isLive: match.isLive))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Carousel

    private var carouselDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<entry.totalTeams, id: \.self) { i in
                Circle()
                    .fill(i == entry.currentIndex ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var carouselControls: some View {
        let prev = (entry.currentIndex - 1 + entry.totalTeams) % entry.totalTeams
        let next = (entry.currentIndex + 1) % entry.totalTeams

        return HStack(spacing: 0) {
            Button(intent: NavigateTeamIntent(newIndex: prev)) {
                Image(systemName: "chevron.left")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 16)
            }
            .buttonStyle(.plain)

            Spacer()
            carouselDots
            Spacer()

            Button(intent: NavigateTeamIntent(newIndex: next)) {
                Image(systemName: "chevron.right")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 16)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Common

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.red).frame(width: 5, height: 5)
            Text("LIVE")
                .font(.caption2).fontWeight(.bold).foregroundStyle(.red)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.red.opacity(0.15))
        .clipShape(Capsule())
    }

    private func teamLogo(data: Data?, size: CGFloat) -> some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "shield.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.secondary.opacity(0.4))
                    )
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Time Helpers

    private func timeText(_ date: Date, isLive: Bool) -> String {
        if isLive { return "경기 진행 중" }
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "오늘 " + date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInTomorrow(date)  { return "내일 " + date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func timeOnly(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func dateText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "오늘" }
        if cal.isDateInTomorrow(date) { return "내일" }
        return date.formatted(.dateTime.month().day())
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    FavoriteTeamWidget()
} timeline: {
    FavoriteTeamEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    FavoriteTeamWidget()
} timeline: {
    FavoriteTeamEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    FavoriteTeamWidget()
} timeline: {
    FavoriteTeamEntry.placeholder
}

#Preview("Lock Circular", as: .accessoryCircular) {
    FavoriteTeamWidget()
} timeline: {
    FavoriteTeamEntry.placeholder
}

#Preview("Lock Rectangular", as: .accessoryRectangular) {
    FavoriteTeamWidget()
} timeline: {
    FavoriteTeamEntry.placeholder
}

#Preview("Lock Inline", as: .accessoryInline) {
    FavoriteTeamWidget()
} timeline: {
    FavoriteTeamEntry.placeholder
}
