//
//  FavoriteTeamWidgetView+Components.swift
//  LOLIVEWidgets
//
//  시간/스코어 표시, 캐러셀, 팀 로고 등 크기별 뷰(+Sizes)에서 공유하는 조각.
//

import AppIntents
import SwiftUI
import WidgetKit

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
                    .widgetAccentable()
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
                .widgetAccentable()
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
                .widgetAccentable()
        } else {
            Text(timeText(match.startTime, isLive: match.isLive))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Small 전용: 대표 팀

    /// Small은 Medium 캐러셀과 상태를 공유하지 않고 항상 "대표 팀"(즐겨찾기 화면에서 지정,
    /// 없으면 즐겨찾기 목록 첫 팀)을 고정으로 보여준다 — Medium에서 다음 팀으로 넘겨도
    /// Small이 같이 넘어가던 문제(같은 위젯 kind가 공용 캐러셀 인덱스를 공유해서 발생)를
    /// Small을 그 인덱스에서 아예 분리해서 해결.
    var representativeTeam: TeamRowInfo? {
        let primaryCode = SharedDataService.loadPrimaryTeamCode()?.uppercased()
        if let primaryCode,
           let match = entry.allTeams.first(where: { $0.teamCode.uppercased() == primaryCode }) {
            return match
        }
        return entry.allTeams.first
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

        // 아이콘 자체는 지금 크기(시각적으로 작게) 그대로 두고, 탭 가능한 영역을 넓힌다 —
        // 너비는 44pt(가로로 넉넉하게), 높이는 36pt. Medium 캔버스가 기기별로 최소 155pt인데
        // 패딩 20 + 이 줄까지 44pt를 그대로 쓰면 나머지 요소가 들어갈 자리가 5pt도 안 남아서
        // 무조건 잘렸다 — 높이만 36으로 줄여서 규격 안에 확실히 들어가게 함.
        return HStack(spacing: 0) {
            Button(intent: NavigateTeamIntent(newIndex: prev)) {
                Image(systemName: "chevron.left")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("이전 팀")

            Spacer()
            carouselDots
            Spacer()

            Button(intent: NavigateTeamIntent(newIndex: next)) {
                Image(systemName: "chevron.right")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("다음 팀")
        }
        .frame(height: 36)
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
        .widgetAccentable()
    }

    func teamLogo(data: Data?, size: CGFloat) -> some View {
        Group {
            // 홈 화면 "테마" 틴트 모드에서는 색깔 있는 로고가 강제로 단색 처리돼 뭉개져 보일 수
            // 있어서, fullColor가 아닐 땐 로고 이미지 대신 방패 아이콘 폴백으로 대체한다.
            if renderingMode == .fullColor, let data, let uiImage = UIImage(data: data) {
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
