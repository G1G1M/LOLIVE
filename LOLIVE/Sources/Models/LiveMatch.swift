//
//  LiveMatch.swift
//  LOLIVE
//

import Foundation

struct LiveMatch: Codable, Identifiable, Hashable {
    var id: String { match.id }
    let match: Match
    let currentSet: Int
    let lastUpdated: Date
}
