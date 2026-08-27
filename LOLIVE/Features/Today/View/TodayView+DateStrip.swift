//
//  TodayView+DateStrip.swift
//  LOLIVE
//
//  Today 화면 상단의 FotMob 스타일 날짜 선택 스트립.
//

import SwiftUI

extension TodayView {

    // MARK: - Fixed: Date Strip

    var dateStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(dateRange, id: \.self) { date in
                        dateChip(date).id(date)
                    }
                }
                .padding(.horizontal, 8)
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                proxy.scrollTo(cal.startOfDay(for: Date()), anchor: .center)
            }
            .onChange(of: selectedDate) { _, newDate in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newDate, anchor: .center)
                }
            }
        }
    }

    private func dateChip(_ date: Date) -> some View {
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isToday    = cal.isDateInToday(date)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedDate = date }
        } label: {
            VStack(spacing: 6) {
                // 요일
                Text(weekdayStr(date))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                // 날짜 숫자 — 선택 시 숫자 뒤에만 원형 accent
                ZStack {
                    Circle()
                        .fill(
                            isSelected ? Color.accentColor
                            : isToday  ? Color.accentColor.opacity(0.12)
                            : Color.clear
                        )
                        .frame(width: 36, height: 36)

                    Text(dayStr(date))
                        .font(.system(size: 17, weight: (isSelected || isToday) ? .bold : .regular))
                        .foregroundStyle(
                            isSelected ? Color.white
                            : isToday  ? Color.accentColor
                            : Color(.label)
                        )
                }
            }
            .frame(width: 52)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private func weekdayStr(_ date: Date) -> String {
        Self.weekdayFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private func dayStr(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }
}
