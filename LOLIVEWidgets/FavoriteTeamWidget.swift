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

// MARK: - Entry

struct FavoriteTeamEntry: TimelineEntry {
    let date: Date
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

    static let placeholder = FavoriteTeamEntry(
        date: .now, teamId: "", teamName: "T1", teamCode: "T1",
        teamImageData: nil, leagueName: "LCK", nextMatch: nil,
        opponentImageData: nil, currentIndex: 0, totalTeams: 1, isConfigured: true
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
                let oneHourBefore = match.startTime.addingTimeInterval(-3600)
                nextUpdate = oneHourBefore > .now ? oneHourBefore : .now.addingTimeInterval(3600)
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
                opponentImageData: nil, currentIndex: 0, totalTeams: 0, isConfigured: false
            )
        }

        var idx = SharedDataService.loadCurrentTeamIndex()
        idx = max(0, min(idx, teams.count - 1))
        let fav = teams[idx]

        async let matchTask   = WidgetNetworkService.fetchNextMatch(leagueId: fav.leagueId, teamCode: fav.teamCode)
        async let teamImgTask = fetchImageData(fav.teamImageURL)
        let (match, teamImg)  = await (matchTask, teamImgTask)
        let oppImg            = await fetchImageData(match?.opponentImageURL)

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
            isConfigured: true
        )
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
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("즐겨찾기 팀")
        .description("즐겨찾기한 팀의 다음 경기 일정을 표시합니다.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Root View

struct FavoriteTeamWidgetView: View {
    let entry: FavoriteTeamEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.isConfigured {
                unconfiguredView
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

    // MARK: - Small (FotMob style)

    private var smallView: some View {
        VStack(spacing: 0) {
            // 팀 로고 + 이름
            VStack(spacing: 5) {
                teamLogo(data: entry.teamImageData, size: 48)
                Text(entry.teamCode)
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
                Text(entry.leagueName)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)

            // 다음 경기 정보
            if let match = entry.nextMatch {
                VStack(spacing: 5) {
                    if match.isLive {
                        liveBadge
                    } else {
                        Text("다음 경기")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        teamLogo(data: entry.opponentImageData, size: 18)
                        Text("vs \(match.opponentCode)")
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Text(timeText(match.startTime, isLive: match.isLive))
                        .font(.caption2).foregroundStyle(.secondary)
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

    // MARK: - Medium (FotMob match card style)

    private var mediumView: some View {
        VStack(spacing: 0) {
            if let match = entry.nextMatch {
                // FotMob 스타일: 팀A — 정보 — 팀B 3열 레이아웃
                HStack(spacing: 0) {
                    // 팀 A
                    VStack(spacing: 5) {
                        teamLogo(data: entry.teamImageData, size: 44)
                        Text(entry.teamCode)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)

                    // 중앙 정보
                    VStack(spacing: 4) {
                        if match.isLive {
                            liveBadge
                            Text("경기 진행 중")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text(timeOnly(match.startTime))
                                .font(.title3).fontWeight(.bold).foregroundStyle(.white)
                            Text(dateText(match.startTime))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(entry.leagueName)
                            .font(.caption2).foregroundStyle(Color.white.opacity(0.4))
                            .padding(.top, 2)
                    }
                    .frame(width: 100)

                    // 팀 B (상대)
                    VStack(spacing: 5) {
                        teamLogo(data: entry.opponentImageData, size: 44)
                        Text(match.opponentCode)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else {
                // 예정 경기 없음
                HStack(spacing: 14) {
                    teamLogo(data: entry.teamImageData, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.teamCode)
                            .font(.title3).fontWeight(.bold).foregroundStyle(.white)
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

    // MARK: - Carousel

    private var carouselDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<entry.totalTeams, id: \.self) { i in
                Circle()
                    .fill(i == entry.currentIndex ? Color.white : Color.white.opacity(0.3))
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
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 28, height: 16)
            }
            .buttonStyle(.plain)

            Spacer()

            carouselDots

            Spacer()

            Button(intent: NavigateTeamIntent(newIndex: next)) {
                Image(systemName: "chevron.right")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.4))
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
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "shield.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(.white.opacity(0.2))
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
