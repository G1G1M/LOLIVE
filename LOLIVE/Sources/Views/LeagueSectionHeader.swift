//
//  LeagueSectionHeader.swift
//  LOLIVE
//

import SwiftUI

struct LeagueSectionHeader: View {
    let league: League

    var body: some View {
        HStack(spacing: 8) {
            CachedAsyncImage(url: URL(string: league.imageURL ?? ""))
                .frame(width: 18, height: 18)

            Text(league.name.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    LeagueSectionHeader(
        league: League(id: "1", slug: "lck", name: "LCK", region: "Korea", imageURL: nil)
    )
    .preferredColorScheme(.dark)
}
