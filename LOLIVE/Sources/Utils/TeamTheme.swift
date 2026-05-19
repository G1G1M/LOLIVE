//
//  TeamTheme.swift
//  LOLIVE
//

import SwiftUI

enum TeamTheme {
    static func color(for teamCode: String) -> Color {
        switch teamCode.uppercased() {
        // LCK
        case "T1":   return Color(red: 0.788, green: 0.008, blue: 0.176)
        case "GEN":  return Color(red: 0.714, green: 0.576, blue: 0.227)
        case "DK":   return Color(red: 0.000, green: 0.341, blue: 0.722)
        case "KT":   return Color(red: 0.839, green: 0.000, blue: 0.141)
        case "DRX":  return Color(red: 0.039, green: 0.298, blue: 0.702)
        case "HLE":  return Color(red: 0.945, green: 0.353, blue: 0.133)
        case "NS":   return Color(red: 0.890, green: 0.094, blue: 0.212)
        case "LSB":  return Color(red: 0.224, green: 0.710, blue: 0.290)
        case "BFX":  return Color(red: 0.000, green: 0.706, blue: 0.847)
        case "DNF":  return Color(red: 0.600, green: 0.400, blue: 1.000)
        // LPL
        case "BLG":  return Color(red: 0.000, green: 0.639, blue: 1.000)
        case "JDG":  return Color(red: 0.000, green: 0.322, blue: 0.655)
        case "EDG":  return Color(red: 0.000, green: 0.400, blue: 1.000)
        case "WBG":  return Color(red: 0.890, green: 0.094, blue: 0.212)
        case "LNG":  return Color(red: 1.000, green: 0.420, blue: 0.000)
        case "NIP":  return Color(red: 1.000, green: 0.851, blue: 0.000)
        case "OMG":  return Color(red: 1.000, green: 0.412, blue: 0.000)
        case "AL":   return Color(red: 0.200, green: 0.600, blue: 1.000)
        case "UP":   return Color(red: 0.600, green: 0.000, blue: 0.800)
        // LEC
        case "FNC":  return Color(red: 0.941, green: 0.655, blue: 0.000)
        case "G2":   return Color(red: 0.769, green: 0.608, blue: 0.235)
        case "VIT":  return Color(red: 0.992, green: 0.894, blue: 0.227)
        case "MAD":  return Color(red: 0.961, green: 0.651, blue: 0.137)
        case "TH":   return Color(red: 0.000, green: 0.749, blue: 0.749)
        case "KC":   return Color(red: 0.000, green: 0.749, blue: 1.000)
        case "BDS":  return Color(red: 0.000, green: 0.502, blue: 1.000)
        case "GX":   return Color(red: 1.000, green: 0.420, blue: 0.000)
        // LCS
        case "C9":   return Color(red: 0.114, green: 0.631, blue: 0.949)
        case "TL":   return Color(red: 0.000, green: 0.698, blue: 1.000)
        case "100":  return Color(red: 0.784, green: 0.063, blue: 0.180)
        case "EG":   return Color(red: 0.047, green: 0.451, blue: 0.804)
        case "FLY":  return Color(red: 0.122, green: 0.561, blue: 1.000)
        case "NRG":  return Color(red: 0.957, green: 0.263, blue: 0.212)
        case "TSM":  return Color(red: 0.067, green: 0.337, blue: 0.580)
        case "DIG":  return Color(red: 0.800, green: 0.000, blue: 0.200)
        default:     return Color.accentColor
        }
    }
}
