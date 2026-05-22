//
//  RoleStyle.swift
//  LOLIVE
//

import SwiftUI

enum RoleStyle {
    static func label(_ role: String) -> String {
        switch role.lowercased() {
        case "top":              return "TOP"
        case "jungle":           return "JGL"
        case "mid":              return "MID"
        case "bottom", "bot":    return "BOT"
        case "support":          return "SUP"
        default:                 return String(role.prefix(3)).uppercased()
        }
    }

    static func color(_ role: String) -> Color {
        switch role.lowercased() {
        case "top":              return .orange
        case "jungle":           return .green
        case "mid":              return .blue
        case "bottom", "bot":    return .red
        case "support":          return .purple
        default:                 return .secondary
        }
    }

    static func order(_ role: String) -> Int {
        switch role.lowercased() {
        case "top":              return 0
        case "jungle":           return 1
        case "mid":              return 2
        case "bottom", "bot":    return 3
        case "support":          return 4
        default:                 return 5
        }
    }
}
