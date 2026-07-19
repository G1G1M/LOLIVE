//
//  PlayerAvatarView.swift
//  LOLIVE
//

import SwiftUI
import UIKit

struct PlayerAvatarView: View {
    let imageURL: String?
    let size: CGFloat

    @State private var uiImage: UIImage? = nil
    @State private var showPlaceholder = true

    var body: some View {
        ZStack {
            if showPlaceholder {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .padding(size * 0.09)
            } else if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .task(id: imageURL) { await load() }
    }

    private func load() async {
        guard let urlStr = imageURL, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            uiImage = nil
            showPlaceholder = true
            return
        }

        let img = await CachedAsyncImage.loadImage(from: url)

        if let img, !isDarkSilhouette(img) {
            uiImage = img
            showPlaceholder = false
        } else {
            uiImage = nil
            showPlaceholder = true
        }
    }

    // 평균 밝기가 0.15 미만이면 Riot API 기본 실루엣 이미지로 판단
    // 투명 배경 PNG는 흰 배경 위에 합성 후 측정 (투명 픽셀이 검정으로 오판되는 현상 방지)
    private func isDarkSilhouette(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }

        let width = 8
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var raw = [UInt8](repeating: 0, count: width * height * 4)

        guard let ctx = CGContext(
            data: &raw,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        // 먼저 흰 배경 채우기 → 투명 픽셀이 흰색(밝기=1)으로 처리됨
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        for i in 0..<(width * height) {
            let r = Double(raw[i * 4])     / 255.0
            let g = Double(raw[i * 4 + 1]) / 255.0
            let b = Double(raw[i * 4 + 2]) / 255.0
            total += (r + g + b) / 3.0
        }
        return (total / Double(width * height)) < 0.15
    }
}
