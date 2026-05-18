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
                .frame(width: 20, height: 20)

            Text(league.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

#Preview {
    LeagueSectionHeader(league: League(id: "1", slug: "lck", name: "LCK", region: "Korea", imageURL: nil))
        .preferredColorScheme(.dark)
}
