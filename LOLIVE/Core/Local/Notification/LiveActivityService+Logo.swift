//
//  LiveActivityService+Logo.swift
//  LOLIVE
//
//  Live Activity에 넘길 팀 로고 준비.
//  ActivityKit attributes는 4KB 제한이 있어 저화질 썸네일만 담을 수 있으므로,
//  고화질 원본은 App Group 공유 컨테이너에 따로 저장해 위젯이 직접 읽게 한다.
//

import ActivityKit
import Foundation
import UIKit
import os

extension LiveActivityService {

    /// App Group 공유 컨테이너의 고화질 로고 디렉토리.
    /// attributes 4KB 제한을 우회하기 위해 위젯이 여기서 파일을 직접 읽는다.
    private static let sharedLogoDir: URL? = {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDataService.appGroupId) else { return nil }
        let dir = base.appendingPathComponent("LiveActivityLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 팀 코드 → 로고 파일명 (경로에 쓸 수 없는 문자 치환).
    /// 위젯 쪽 sharedHiResLogo(teamCode:)와 동일한 규칙이어야 한다.
    private static func logoFileName(teamCode: String) -> String {
        teamCode
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_") + ".png"
    }

    /// 원본 이미지를 고화질 PNG로 App Group에 저장.
    ///
    /// [화질 원칙]
    /// - 업스케일 금지: 원본이 목표보다 작으면 원본 해상도 그대로 저장 (억지로 키우면 뭉개짐)
    /// - 비율 유지: 정사각 캔버스에 scaledToFit으로 그리고 여백은 투명 처리
    /// - 목표 300px: 잠금화면 로고 38pt(@3x=114px) 대비 충분한 여유
    ///
    /// 렌더링·PNG 인코딩·파일 쓰기는 CPU 바운드 작업이라 `Task.detached`로 메인 스레드 밖에서 수행한다
    /// (CachedAsyncImage.loadImage와 동일한 패턴). 경기가 라이브로 전환되는 시점은 UI가 바쁠 때라 중요하다.
    func saveHiResLogo(_ original: UIImage, teamCode: String) async {
        guard let dir = Self.sharedLogoDir else { return }

        let logoPath = dir.appendingPathComponent(Self.logoFileName(teamCode: teamCode))
        let savedInfo = await Task.detached(priority: .utility) { () -> (side: Int, bytes: Int)? in
            // 원본의 실제 픽셀 크기 (UIImage.size는 포인트 단위이므로 scale 곱)
            let originalPx = CGSize(width: original.size.width * original.scale,
                                    height: original.size.height * original.scale)
            let maxOriginalSide = max(originalPx.width, originalPx.height)
            guard maxOriginalSide > 0 else { return nil }

            let side = min(300, maxOriginalSide)  // 업스케일 방지
            let ratio = side / maxOriginalSide
            let drawSize = CGSize(width: originalPx.width * ratio,
                                  height: originalPx.height * ratio)
            let origin = CGPoint(x: (side - drawSize.width) / 2,
                                 y: (side - drawSize.height) / 2)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                                   format: format)
            let image = renderer.image { _ in
                original.draw(in: CGRect(origin: origin, size: drawSize))
            }
            guard let png = image.pngData() else { return nil }
            try? png.write(to: logoPath, options: .atomic)
            return (Int(side), png.count)
        }.value

        if let savedInfo {
            logger.debug("🖼️ [\(teamCode)] 고화질 로고 저장 (\(savedInfo.side)px, \(savedInfo.bytes) bytes, App Group)")
        }
    }

    /// URL에서 이미지를 fetch해 소형 PNG 썸네일로 변환 후 반환.
    /// 반환된 Data는 MatchActivityAttributes에 직접 포함되어 ActivityKit이 위젯 Extension에 전달.
    ///
    /// [크기 제한] ActivityKit은 attributes 전체를 4KB로 제한한다 (초과 시 attributesTooLarge).
    /// 이미지 2장 + 텍스트가 들어가므로 이미지 1장당 최대 1.5KB로 맞추고,
    /// 초과하면 해상도를 단계적으로 낮춰 재시도한다 (복잡한 로고 PNG 대응).
    func fetchThumbnail(urlString: String?, teamCode: String) async -> Data? {
        guard let str = urlString, let url = URL(string: str) else {
            logger.debug("🖼️ [\(teamCode)] URL 없음")
            return nil
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            logger.debug("🖼️ [\(teamCode)] 네트워크 fetch 실패")
            return nil
        }
        guard let original = UIImage(data: data) else {
            logger.debug("🖼️ [\(teamCode)] UIImage 변환 실패")
            return nil
        }

        // 고화질 버전을 App Group에 저장 — 위젯이 우선 사용 (4KB 제한 없음)
        await saveHiResLogo(original, teamCode: teamCode)

        // 투명 배경 유지를 위해 PNG 고정.
        // 큰 해상도부터 시도해 예산 안에 들어오는 가장 선명한 크기를 사용.
        // (90px = 기존 30pt@3x와 동일 화질 — 단순한 로고는 그대로 유지됨)
        // 렌더링·인코딩은 CPU 바운드라 메인 스레드 밖(Task.detached)에서 수행한다.
        //
        // [예산 900B인 이유] ActivityKit은 attributes를 JSON(Data→base64)으로 인코딩해 전달한다.
        // base64는 원본보다 약 37% 커지므로, 로고가 복잡해 압축이 잘 안 되는 팀(T1·Gen.G 등)은
        // 기존 1500B 예산도 base64 변환 후 이미지 2장만으로 4KB를 넘겨 attributesTooLarge로
        // Activity.request 자체가 거부되는 버그가 있었다. 900B(base64 후 약 1.2KB) × 2장 +
        // 팀명/코드/리그명 여유를 두어도 4KB 한도 안에 들어오도록 낮춘다.
        let maxBytes = 900
        let sides = [90, 72, 60, 48, 36, 30, 24, 16, 12]
        let result = await Task.detached(priority: .utility) { () -> (side: Int, png: Data)? in
            let originalPx = CGSize(width: original.size.width * original.scale,
                                    height: original.size.height * original.scale)
            let maxOriginalSide = max(originalPx.width, originalPx.height, 1)
            for side in sides {
                let canvas = CGFloat(side)
                // 비율 유지: 정사각 캔버스에 scaledToFit, 여백은 투명
                let ratio = min(canvas / maxOriginalSide, 1)  // 업스케일 방지
                let drawSize = CGSize(width: originalPx.width * ratio,
                                      height: originalPx.height * ratio)
                let origin = CGPoint(x: (canvas - drawSize.width) / 2,
                                     y: (canvas - drawSize.height) / 2)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1  // @2x/@3x 렌더링 방지 — 픽셀 수가 그대로 파일 크기로 이어짐
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas),
                                                       format: format)
                let thumbnail = renderer.image { _ in
                    original.draw(in: CGRect(origin: origin, size: drawSize))
                }
                guard let png = thumbnail.pngData() else { continue }
                if png.count <= maxBytes { return (side, png) }
            }
            return nil
        }.value

        if let result {
            logger.debug("🖼️ [\(teamCode)] ✅ 썸네일 준비: \(result.png.count) bytes (\(result.side)×\(result.side) PNG)")
            return result.png
        }
        // 12×12로도 1.5KB를 넘으면 이미지 생략 → 위젯은 팀 코드 텍스트로 폴백
        logger.debug("🖼️ [\(teamCode)] ⚠️ 압축 실패 — 이미지 생략")
        return nil
    }
}
