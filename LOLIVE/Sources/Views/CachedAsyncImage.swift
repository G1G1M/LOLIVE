//
//  CachedAsyncImage.swift
//  LOLIVE
//

import SwiftUI
import UIKit
import CryptoKit

struct CachedAsyncImage: View {
    let url: URL?

    @State private var uiImage: UIImage? = nil

    // 메모리 캐시 (internal — PlayerAvatarView에서도 공유)
    static let memCache = NSCache<NSString, UIImage>()

    // 디스크 캐시 디렉토리 (internal)
    static let diskDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("image_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        uiImage = await Self.loadImage(from: url)
    }

    // 외부(PlayerAvatarView 등)에서 공용으로 사용할 수 있는 정적 로더
    static func loadImage(from url: URL?) async -> UIImage? {
        guard let url else { return nil }
        let key     = url.absoluteString as NSString
        let fileURL = diskDir.appendingPathComponent(diskKey(for: url))

        if let cached = memCache.object(forKey: key) { return cached }

        if let img = await Task.detached(priority: .userInitiated, operation: {
            guard let data = try? Data(contentsOf: fileURL) else { return nil as UIImage? }
            return UIImage(data: data)
        }).value {
            memCache.setObject(img, forKey: key)
            return img
        }

        var request = URLRequest(url: url)
        if url.host?.contains("fandom.com") == true || url.host?.contains("wikia") == true {
            request.setValue("https://lol.fandom.com", forHTTPHeaderField: "Referer")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let img = UIImage(data: data) else { return nil }

        memCache.setObject(img, forKey: key)
        let dataToSave = data
        Task.detached(priority: .background) {
            try? dataToSave.write(to: fileURL, options: .atomic)
        }
        return img
    }

    static func diskKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
