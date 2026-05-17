//
//  Player.swift
//  LOLIVE
//

import Foundation

struct Player: Identifiable, Hashable {
    let id: String
    let summonerName: String
    let firstName: String?
    let lastName: String?
    let role: String
    let imageURL: String?
    let teamId: String
    let teamCode: String
}
