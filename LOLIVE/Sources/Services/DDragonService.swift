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
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(v)/img/champion/\(championId).png")
    }

    private func fetchLatestVersion() async -> String? {
        guard let url = URL(string: "https://ddragon.leagueoflegends.com/api/versions.json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let versions = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return versions.first
    }
}
