//
//  League.swift
//  LOLIVE
//

import Foundation

struct League: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let region: String
    let imageURL: String?
}
