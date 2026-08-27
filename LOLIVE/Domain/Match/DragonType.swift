//
//  DragonType.swift
//  LOLIVE
//
//  Riot 라이브 스탯 피드가 주는 드래곤 종류 문자열을 화면 표기로 옮긴다.
//  실측으로 확인한 값: infernal / ocean / cloud / mountain / hextech / chemtech / elder
//  (`window` 응답의 `blueTeam.dragons` 배열, 획득 순서대로 들어온다)
//

import SwiftUI

enum DragonType: String, CaseIterable {
    case infernal
    case ocean
    case cloud
    case mountain
    case hextech
    case chemtech
    case elder

    /// 피드가 예상 밖의 값을 주면 nil — 모르는 종류를 추측해서 라벨 붙이지 말 것.
    init?(feedValue: String) {
        self.init(rawValue: feedValue.lowercased().trimmingCharacters(in: .whitespaces))
    }

    var shortLabel: String {
        switch self {
        case .infernal: return "화염"
        case .ocean:    return "바다"
        case .cloud:    return "바람"
        case .mountain: return "대지"
        case .hextech:  return "마공"
        case .chemtech: return "화공"
        case .elder:    return "장로"
        }
    }

    var color: Color {
        switch self {
        case .infernal: return .red
        case .ocean:    return .cyan
        case .cloud:    return .mint
        case .mountain: return .brown
        case .hextech:  return .blue
        case .chemtech: return .green
        case .elder:    return .purple
        }
    }

    var symbolName: String {
        switch self {
        case .infernal: return "flame.fill"
        case .ocean:    return "drop.fill"
        case .cloud:    return "wind"
        case .mountain: return "mountain.2.fill"
        case .hextech:  return "bolt.fill"
        case .chemtech: return "leaf.fill"
        case .elder:    return "crown.fill"
        }
    }
}

extension TeamGameStats {
    /// 알아본 드래곤만 순서대로. 피드에 종류 정보가 없던 예전 캐시면 빈 배열.
    var recognizedDragons: [DragonType] {
        (dragonTypes ?? []).compactMap(DragonType.init(feedValue:))
    }
}
