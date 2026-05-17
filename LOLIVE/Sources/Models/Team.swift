//
//  Team.swift
//  LOLIVE
//

import Foundation

struct Team: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let code: String
    let imageURL: String?
}
