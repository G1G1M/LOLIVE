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

    // 1단계: 메모리 캐시 (세션 내 즉시 반환)
    private static let memCache = NSCache<NSString, UIImage>()

    // 2단계: 디스크 캐시 디렉토리
    private static let diskDir: URL = {
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
        guard let url else { uiImage = nil; return }
        let key     = url.absoluteString as NSString
        let fileURL = Self.diskDir.appendingPathComponent(diskKey(for: url))

        // 1. 메모리 캐시 확인
        if let cached = Self.memCache.object(forKey: key) {
            uiImage = cached
            return
        }

        // 2. 디스크 캐시 확인 (백그라운드 스레드에서 읽기)
        if let img = await Task.detached(priority: .userInitiated, operation: {
            guard let data = try? Data(contentsOf: fileURL) else { return nil as UIImage? }
            return UIImage(data: data)
        }).value {
            Self.memCache.setObject(img, forKey: key)
            uiImage = img
            return
        }

        // 3. 네트워크 다운로드
        uiImage = nil
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }

        Self.memCache.setObject(img, forKey: key)
        uiImage = img

        // 디스크 저장 (백그라운드, 완료 기다리지 않음)
        let dataToSave = data
        Task.detached(priority: .background) {
            try? dataToSave.write(to: fileURL, options: .atomic)
        }
    }

    // URL → SHA256 해시 파일명 (특수문자 없이 고정 길이)
    private func diskKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
