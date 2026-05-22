//
//  Tournament.swift
//  LOLIVE
//

import Foundation

struct Tournament: Codable, Identifiable {
    let id: String
    let slug: String
    let startDate: String   // "2025-01-15" 형식
    let endDate: String
}
