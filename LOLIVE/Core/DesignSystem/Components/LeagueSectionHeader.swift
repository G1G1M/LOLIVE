//
//  LeagueSectionHeader.swift
//  LOLIVE
//

import SwiftUI

struct LeagueSectionHeader: View {
    let league: League

    var body: some View {
        HStack(spacing: 8) {
            LogoBadgeView(imageURL: league.imageURL, size: 18)

            Text(league.name.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        // 헤더로 표시해야 VoiceOver 로터의 "머리말"로 리그 단위 건너뛰기가 된다.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(league.name)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    LeagueSectionHeader(
        league: League(id: "1", slug: "lck", name: "LCK", region: "Korea", imageURL: nil)
    )
    .preferredColorScheme(.dark)
}
