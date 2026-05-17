//
//  Standing.swift
//  LOLIVE
//

import Foundation

struct Standing: Codable, Identifiable, Hashable {
    var id: String { team.id }
    let team: Team
    let wins: Int
    let losses: Int
    let rank: Int
    let winRate: Double
}
