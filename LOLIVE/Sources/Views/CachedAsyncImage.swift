//
//  CachedAsyncImage.swift
//  LOLIVE
//

import SwiftUI
import UIKit

struct CachedAsyncImage: View {
    let url: URL?

    @State private var uiImage: UIImage? = nil

    private static let cache = NSCache<NSString, UIImage>()

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
        let key = url.absoluteString as NSString
        if let cached = Self.cache.object(forKey: key) {
            uiImage = cached
            return
        }
        uiImage = nil
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        Self.cache.setObject(img, forKey: key)
        uiImage = img
    }
}
