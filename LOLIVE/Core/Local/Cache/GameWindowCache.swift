//
//  GameWindowCache.swift
//  LOLIVE
//

import Foundation

/// 완료된 게임의 윈도우 데이터를 디스크에 캐시.
/// 완료 게임은 데이터가 변하지 않으므로 만료 기한 없이 영구 저장.
actor GameWindowCache {

    static let shared = GameWindowCache()

    private var memory: [String: GameWindow] = [:]

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameWindows", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Read

    func window(for gameId: String) -> GameWindow? {
        if let cached = memory[gameId] { return cached }
        let file = Self.cacheFile(for: gameId)
        guard let data = try? Data(contentsOf: file),
              let window = try? JSONDecoder().decode(GameWindow.self, from: data) else { return nil }
        memory[gameId] = window
        return window
    }

    // MARK: - Write

    func save(_ window: GameWindow) {
        memory[window.gameId] = window
        let file = Self.cacheFile(for: window.gameId)
        if let data = try? JSONEncoder().encode(window) {
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: - Private

    private static func cacheFile(for gameId: String) -> URL {
        cacheDir.appendingPathComponent("\(gameId).json")
    }
}
