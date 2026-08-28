//
//  ImageDownsampleTests.swift
//  LOLIVETests
//
//  팀 로고·챔피언 아이콘 디코딩 크기 제한 테스트.
//  원본 그대로 디코딩하면 로고 한 장이 수십~수백 MB를 먹어서(실측 8334×8334 = 265MB)
//  메모리 캐시가 금방 터진다. 표시 크기에 맞게 줄여서 디코딩하는지 고정한다.
//

import Testing
import Foundation
import UIKit
@testable import LOLIVE

private func makePNG(width: Int, height: Int) -> Data {
    let size = CGSize(width: width, height: height)
    let renderer = UIGraphicsImageRenderer(size: size, format: {
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = 1
        return f
    }())
    let image = renderer.image { ctx in
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
    return image.pngData()!
}

@Suite("이미지 다운샘플링")
struct ImageDownsampleTests {

    @Test("큰 원본은 256px 이하로 줄여서 디코딩한다")
    func downsamplesLargeImage() throws {
        let data = makePNG(width: 2000, height: 2000)
        let image = try #require(CachedAsyncImage.downsampled(data))
        let cg = try #require(image.cgImage)
        #expect(cg.width <= 256)
        #expect(cg.height <= 256)
    }

    @Test("가로세로 비율을 유지한다")
    func keepsAspectRatio() throws {
        let data = makePNG(width: 1000, height: 500)
        let image = try #require(CachedAsyncImage.downsampled(data))
        let cg = try #require(image.cgImage)
        let ratio = Double(cg.width) / Double(cg.height)
        #expect(abs(ratio - 2.0) < 0.05)
        #expect(cg.width <= 256)
    }

    @Test("이미 작은 이미지는 키우지 않는다")
    func doesNotUpscale() throws {
        let data = makePNG(width: 64, height: 64)
        let image = try #require(CachedAsyncImage.downsampled(data))
        let cg = try #require(image.cgImage)
        #expect(cg.width == 64)
        #expect(cg.height == 64)
    }

    @Test("큰 원본의 디코딩 비용이 1MB 아래로 떨어진다")
    func costStaysSmall() throws {
        let data = makePNG(width: 3000, height: 3000)
        let image = try #require(CachedAsyncImage.downsampled(data))
        let cost = CachedAsyncImage.cost(of: image)
        // 원본 그대로면 3000*3000*4 = 34MB
        #expect(cost > 0)
        #expect(cost < 1024 * 1024)
    }

    @Test("이미지가 아닌 데이터는 nil")
    func rejectsNonImageData() {
        #expect(CachedAsyncImage.downsampled(Data("이건 이미지가 아님".utf8)) == nil)
    }
}
