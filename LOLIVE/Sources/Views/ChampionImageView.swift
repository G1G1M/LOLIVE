//
//  ChampionImageView.swift
//  LOLIVE
//

import SwiftUI

struct ChampionImageView: View {
    let championId: String
    let size: CGFloat

    @State private var imageURL: URL?

    var body: some View {
        CachedAsyncImage(url: imageURL)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
            .task(id: championId) {
                imageURL = await DDragonService.shared.championImageURL(for: championId)
            }
    }
}
