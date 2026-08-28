//
//  CachedAsyncImage.swift
//  LOLIVE
//

import SwiftUI
import UIKit
import CryptoKit
import ImageIO

struct CachedAsyncImage: View {
    let url: URL?

    @State private var uiImage: UIImage? = nil

    // 메모리 캐시 (internal — PlayerAvatarView에서도 공유)
    static let memCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // 비용은 디코딩된 바이트 수로 넣는다(아래 cost(of:)). 상한이 없으면 NSCache는
        // 메모리 경고가 뜰 때까지 계속 쌓아두는데, 그때 비워지면 스크롤 중에 다시 디코딩된다.
        c.totalCostLimit = 32 * 1024 * 1024
        c.countLimit = 300
        return c
    }()

    /// 앱에서 이 이미지를 가장 크게 쓰는 곳이 72pt(팀 상세 헤더)라, 3배 화면 기준 216px이면 충분하다.
    /// 여유를 둬서 256px로 잡는다.
    private static let maxPixelSize = 256

    /// 원본 그대로 디코딩하면 안 된다.
    /// 실측: 캐시된 로고 248장 중 8334×8334(디코딩 시 265MB)·4000×4000(61MB)·3000×3000(34MB)이
    /// 섞여 있고, 전부 디코딩하면 1.2GB가 넘는다(파일로는 35MB). 36pt 자리에 쓰는 이미지들이다.
    /// ImageIO 썸네일로 축소해서 디코딩하면 한 장당 256KB 이하로 떨어진다.
    ///
    /// `kCGImageSourceShouldCacheImmediately`는 여기서(백그라운드) 바로 디코딩하게 한다 —
    /// `UIImage(data:)`는 디코딩을 미뤄서 화면에 처음 그려지는 순간 메인 스레드에서 풀린다.
    static func downsampled(_ data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return UIImage(data: data)   // 썸네일을 못 만드는 형식이면 원본으로 폴백
        }
        return UIImage(cgImage: thumbnail)
    }

    /// NSCache 비용 = 디코딩된 실제 바이트 수.
    static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

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
            return downsampled(data)
        }).value {
            memCache.setObject(img, forKey: key, cost: cost(of: img))
            return img
        }

        var request = URLRequest(url: url)
        if url.host?.contains("fandom.com") == true || url.host?.contains("wikia") == true {
            request.setValue("https://lol.fandom.com", forHTTPHeaderField: "Referer")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        // 디코딩·축소도 메인 스레드 밖에서 한다(원본이 수천 픽셀짜리라 비용이 크다).
        guard let img = await Task.detached(priority: .userInitiated, operation: {
            downsampled(data)
        }).value else { return nil }

        memCache.setObject(img, forKey: key, cost: cost(of: img))
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
