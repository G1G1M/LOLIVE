//
//  OracleElixirService+LeagueMapping.swift
//  LOLIVE
//
//  Riot API의 리그 표기를 Oracle's Elixir 쪽 리그 이름으로 옮기는 대조표.
//  두 소스가 서로 다른 표기를 쓰기 때문에(약칭 vs 정식 명칭) 새 리그를 지원할 때는
//  여기에 한 줄만 추가하면 된다.
//

import Foundation

extension OracleElixirService {

    /// Riot API League → Oracle's Elixir 리그 이름(`/tournaments/byLeague`의 키) 변환.
    /// 지원하지 않는 리그는 nil 반환.
    static func oracleElixirLeagueName(for league: League) -> String? {
        let lower = league.name.lowercased().trimmingCharacters(in: .whitespaces)
        let slug  = league.slug.lowercased().trimmingCharacters(in: .whitespaces)
        switch true {
        case lower == "worlds" || slug == "worlds" ||
             lower.contains("world championship"):                      return "World Championship"
        case lower == "msi" || slug == "msi" ||
             lower.contains("mid-season"):                              return "Mid-Season Invitational"
        case lower == "lck" || slug == "lck":                         return "LoL Champions Korea"
        case lower.contains("챌린저스") && (lower.contains("lck") || slug.contains("lck")),
             lower.contains("challengers") && (lower.contains("lck") || slug.contains("lck")),
             lower == "lck cl", slug == "lck-cl", slug == "lck_cl",
             slug == "lck_challengers_league":                         return "LCK Challengers League"
        case lower == "lpl" || slug == "lpl":                         return "Tencent LoL Pro League"
        case (lower.contains("lpl") || slug.contains("lpl")) &&
             (lower.contains("dev") || lower.contains("ldl") ||
              slug.contains("dev") || slug.contains("ldl")):          return "LoL Development League"
        case lower == "lec" || slug == "lec",
             lower.contains("emea championship"):                      return "LoL EMEA Championship"
        case lower == "lcs" || slug == "lcs":                         return "League of Legends Championship Series"
        case (lower.contains("lcs") || slug.contains("lcs")) &&
             (lower.contains("acad") || slug.contains("acad")):       return "NA Academy League"
        case lower == "pcs" || slug == "pcs":                         return "Pacific Championship Series"
        case lower == "vcs" || slug == "vcs":                         return "Vietnam Championship Series"
        case lower == "cblol" || slug == "cblol":                     return "Circuit Brazilian League of Legends"
        case (lower.contains("cblol") || slug.contains("cblol")) &&
             (lower.contains("acad") || slug.contains("acad")):       return "Circuit Brazilian League of Legends Academy"
        case lower == "ljl" || slug == "ljl":                         return "LoL Japan League"
        case lower == "lco" || slug == "lco":                         return "LoL Circuit Oceania"
        case lower == "lla" || slug == "lla":                         return "Liga Latinoamerica"
        case lower == "lcp" || slug == "lcp":                         return "League of Legends Championship Pacific"
        case lower == "kespa cup" || slug == "kespa_cup" ||
             lower.contains("kespa"):                                  return "KeSPA Cup"
        default:                                                        return nil
        }
    }
}
