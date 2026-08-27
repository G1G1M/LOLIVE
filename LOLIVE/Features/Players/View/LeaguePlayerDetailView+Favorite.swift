//
//  LeaguePlayerDetailView+Favorite.swift
//  LOLIVE
//
//  선수 즐겨찾기 토글.
//

import SwiftUI
import SwiftData

extension LeaguePlayerDetailView {
    // MARK: - Favorite

    func checkFavoriteStatus() {
        let id = player.id
        let descriptor = FetchDescriptor<FavoritePlayer>(predicate: #Predicate { $0.playerId == id })
        isFavorited = (try? modelContext.fetch(descriptor))?.isEmpty == false
    }

    func toggleFavorite() {
        let id = player.id
        let descriptor = FetchDescriptor<FavoritePlayer>(predicate: #Predicate { $0.playerId == id })
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            existing.forEach { modelContext.delete($0) }
            isFavorited = false
        } else {
            modelContext.insert(FavoritePlayer(player: player, league: league))
            isFavorited = true
        }
    }
}
