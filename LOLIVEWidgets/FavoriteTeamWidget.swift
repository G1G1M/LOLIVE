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

    static let placeholder = FavoriteTeamEntry(
        date: .now, teamId: "", teamName: "T1", teamCode: "T1",
        teamImageData: nil, leagueName: "LCK", nextMatch: nil,
        opponentImageData: nil, currentIndex: 0, totalTeams: 1, isConfigured: true,
        allTeams: []
    )
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
            if let match = entry.nextMatch, !match.isLive {
                let timeToMatch = match.startTime.timeIntervalSinceNow
                if timeToMatch > 3600 {
                    nextUpdate = match.startTime.addingTimeInterval(-3600)
                } else if timeToMatch > 0 {
                    nextUpdate = .now.addingTimeInterval(300)   // 1시간 이내: 5분마다
                } else {
                    nextUpdate = .now.addingTimeInterval(900)   // 경기 시작 후: 15분마다
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

        // 현재 선택 팀 (Small / Medium)
        var idx = SharedDataService.loadCurrentTeamIndex()
        idx = max(0, min(idx, teams.count - 1))
        let fav = teams[idx]

        async let matchTask   = WidgetNetworkService.fetchNextMatch(leagueId: fav.leagueId, teamCode: fav.teamCode)
        async let teamImgTask = fetchImageData(fav.teamImageURL)
        let (match, teamImg)  = await (matchTask, teamImgTask)
        // 상대팀 이미지: 네트워크 fetch 실패 시 App Group 캐시에서 폴백
        let oppImg = await fetchImageData(match?.opponentImageURL)
                   ?? SharedDataService.loadTeamImageData(teamCode: match?.opponentCode ?? "")

        // 전체 팀 (Large 위젯)
        let allTeamsData = await loadAllTeams(teams)

        return FavoriteTeamEntry(
            date: .now,
            teamId: fav.teamId,
            teamName: fav.teamName,
            teamCode: fav.teamCode,
            teamImageData: teamImg,
            leagueName: fav.leagueName,
            nextMatch: match,
            opponentImageData: oppImg,
            currentIndex: idx,
            totalTeams: teams.count,
            isConfigured: true,
            allTeams: allTeamsData
        )
    }

    private func loadAllTeams(_ teams: [SharedFavoriteTeam]) async -> [TeamRowInfo] {
        await withTaskGroup(of: (Int, TeamRowInfo).self) { group in
            for (i, fav) in teams.enumerated() {
                group.addTask {
                    async let m   = WidgetNetworkService.fetchNextMatch(leagueId: fav.leagueId, teamCode: fav.teamCode)
                    async let img = fetchImageData(fav.teamImageURL)
                    let (match, teamImg) = await (m, img)
                    let oppImg = await fetchImageData(match?.opponentImageURL)
                               ?? SharedDataService.loadTeamImageData(teamCode: match?.opponentCode ?? "")
                    return (i, TeamRowInfo(
                        teamCode: fav.teamCode,
                        teamName: fav.teamName,
                        leagueName: fav.leagueName,
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
            } else {
                smallView
            }
        }
        .widgetURL(URL(string: "lolive://team/\(entry.teamId)"))
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
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

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
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Time Views

    @ViewBuilder
    private func matchTimeView(match: WidgetNetworkService.NextMatchInfo, compact: Bool) -> some View {
        let timeToMatch = match.startTime.timeIntervalSinceNow
        if !match.isLive, timeToMatch > 0, timeToMatch <= 3600 {
            // 1시간 이내: 라이브 카운트다운
            VStack(spacing: 1) {
                Text(match.startTime, style: .timer)
                    .font(compact ? .caption2 : .title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: compact ? 44 : 72, alignment: .center)
                Text("후 시작").font(.system(size: 9)).foregroundStyle(.secondary)
            }
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
