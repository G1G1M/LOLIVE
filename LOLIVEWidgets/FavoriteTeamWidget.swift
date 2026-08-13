//
//  FavoriteTeamWidget.swift
//  LOLIVEWidgets
//
//  [파일 구조]
//    - FavoriteTeamWidget.swift                코어(Widget 선언, 크기별 분기, 잠금화면 뷰)
//    - FavoriteTeamProvider.swift               타임라인 데이터 조회 로직(TeamRowInfo/Entry/Provider)
//    - FavoriteTeamWidgetView+Sizes.swift        Small/Medium/Large 크기별 뷰
//    - FavoriteTeamWidgetView+Components.swift   시간/스코어/캐러셀 등 공용 조각
//
//  Extension에서 접근해야 하므로 entry는 internal로 선언되어 있다.
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
    @Environment(\.widgetRenderingMode) var renderingMode

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
                    .accessibilityHidden(true)
            } else {
                Text(entry.teamCode)
                    .font(.caption2).fontWeight(.bold)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.teamName)
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
                    Text("● " + (scoreText(match) ?? "LIVE"))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessoryAccessibilityLabel)
    }

    private var accessoryAccessibilityLabel: String {
        guard let match = entry.nextMatch else { return "\(entry.teamName), 경기 없음" }
        if match.isLive {
            return "\(entry.teamName) vs \(match.opponentName), \(scoreText(match) ?? "라이브")"
        }
        return "\(entry.teamName), \(entry.leagueName), 다음 경기 vs \(match.opponentName)"
    }

    /// 인라인 (잠금화면 시계 위/아래 한 줄)
    private var accessoryInlineView: some View {
        Group {
            if let match = entry.nextMatch {
                if match.isLive {
                    Text("\(entry.teamCode) vs \(match.opponentCode) · " + (scoreText(match) ?? "LIVE"))
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

    /// "1 - 0 · Game 2" 형태의 라이브 스코어 텍스트 — 데이터 없으면 nil.
    /// Sizes 뷰(largeTeamRow)에서도 쓰므로 internal.
    func scoreText(_ match: WidgetNetworkService.NextMatchInfo) -> String? {
        guard let my = match.myScore, let opp = match.oppScore else { return nil }
        guard let game = match.currentGame else { return "\(my) - \(opp)" }
        return "\(my) - \(opp) · Game \(game)"
    }

    private func accessoryTimeText(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date)    { return "오늘 \(time)" }
        if cal.isDateInTomorrow(date) { return "내일 \(time)" }
        return date.formatted(.dateTime.month().day()) + " \(time)"
    }

    // MARK: - Unconfigured

    var unconfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.slash")
                .font(.title2).foregroundStyle(.secondary)
            Text("즐겨찾기한 팀이 없습니다")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
