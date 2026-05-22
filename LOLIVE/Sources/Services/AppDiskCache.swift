//
//  AppDiskCache.swift
//  LOLIVE
//

import Foundation

struct AppDiskCache {

    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("riot_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct Envelope<T: Codable>: Codable {
        let value: T
        let savedAt: Date
    }

    /// 캐시에서 값을 읽습니다. maxAge 초 이내의 데이터만 반환하며, 만료된 파일은 자동 삭제합니다.
    static func get<T: Codable>(key: String, maxAge: TimeInterval) -> T? {
        let file = fileURL(for: key)
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let envelope = try? decoder.decode(Envelope<T>.self, from: data) else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        guard Date().timeIntervalSince(envelope.savedAt) < maxAge else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return envelope.value
    }

    /// 값을 디스크에 저장합니다.
    static func set<T: Codable>(key: String, value: T) {
        let envelope = Envelope(value: value, savedAt: Date())
        guard let data = try? encoder.encode(envelope) else { return }
        try? data.write(to: fileURL(for: key), options: Data.WritingOptions.atomic)
    }

    /// 특정 키의 캐시를 삭제합니다.
    static func clear(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private static func fileURL(for key: String) -> URL {
        let safe = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent("\(safe).json")
    }
}
