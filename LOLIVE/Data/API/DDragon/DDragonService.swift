//
//  DDragonService.swift
//  LOLIVE
//

import Foundation

actor DDragonService {
    static let shared = DDragonService()

    private var version: String?

    func championImageURL(for championId: String) async -> URL? {
        if version == nil {
            version = await fetchLatestVersion()
        }
        let v = version ?? "15.10.1"
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(v)/img/champion/\(Self.normalizedId(championId)).png")
    }

    /// 아이템 아이콘. 라이브 스탯 피드의 `details`가 아이템을 숫자 ID로만 주기 때문에
    /// 여기서 이미지 경로로 옮긴다. 빈 슬롯(0)은 호출부에서 걸러서 넘길 것.
    func itemImageURL(for itemId: Int) async -> URL? {
        guard itemId > 0 else { return nil }
        if version == nil {
            version = await fetchLatestVersion()
        }
        let v = version ?? "15.10.1"
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(v)/img/item/\(itemId).png")
    }

    /// Leaguepedia가 주는 챔피언 표시 이름(예: "Kai'Sa", "Wukong")과 Data Dragon 이미지 경로가
    /// 요구하는 내부 ID(예: "Kaisa", "MonkeyKing")가 다른 챔피언들이 있음 — 실제 Data Dragon
    /// champion.json과 대조해서 확인한 예외 9개. 나머지는 공백/아포스트로피/마침표/앰퍼샌드만
    /// 제거하면 내부 ID와 일치한다(예: "Jarvan IV" → "JarvanIV", "Dr. Mundo" → "DrMundo").
    private static let nameExceptions: [String: String] = [
        "Bel'Veth": "Belveth",
        "Cho'Gath": "Chogath",
        "Kai'Sa": "Kaisa",
        "Kha'Zix": "Khazix",
        "Vel'Koz": "Velkoz",
        "LeBlanc": "Leblanc",
        "Wukong": "MonkeyKing",
        "Nunu & Willump": "Nunu",
        "Renata Glasc": "Renata",
    ]

    static func normalizedId(_ championName: String) -> String {
        if let mapped = nameExceptions[championName] { return mapped }
        return championName
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "&", with: "")
    }

    private func fetchLatestVersion() async -> String? {
        guard let url = URL(string: "https://ddragon.leagueoflegends.com/api/versions.json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let versions = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return versions.first
    }
}
