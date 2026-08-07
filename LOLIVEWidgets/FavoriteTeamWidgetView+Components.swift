//
//  FavoriteTeamWidgetView+Components.swift
//  LOLIVEWidgets
//
//  시간/스코어 표시, 캐러셀, 팀 로고 등 크기별 뷰(+Sizes)에서 공유하는 조각.
//

import AppIntents
import SwiftUI

extension FavoriteTeamWidgetView {

    // MARK: - Time Views

    @ViewBuilder
    func matchTimeView(match: WidgetNetworkService.NextMatchInfo, compact: Bool) -> some View {
        let timeToMatch = match.startTime.timeIntervalSinceNow
        if match.isLive {
            if let score = scoreText(match) {
                Text(score)
                    .font(compact ? .caption2 : .title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("경기 진행 중")
                    .font(compact ? .caption2 : .subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if timeToMatch > 0, timeToMatch <= 3600 {
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
    func largeMatchTimeView(match: WidgetNetworkService.NextMatchInfo) -> some View {
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

    var carouselDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<entry.totalTeams, id: \.self) { i in
                Circle()
                    .fill(i == entry.currentIndex ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
    }

    var carouselControls: some View {
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

    var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.red).frame(width: 5, height: 5)
            Text("LIVE")
                .font(.caption2).fontWeight(.bold).foregroundStyle(.red)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.red.opacity(0.15))
        .clipShape(Capsule())
    }

    func teamLogo(data: Data?, size: CGFloat) -> some View {
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
