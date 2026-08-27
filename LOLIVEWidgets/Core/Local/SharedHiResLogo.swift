//
//  SharedHiResLogo.swift
//  LOLIVEWidgets
//
//  Live Activity와 위젯이 함께 쓰는 고화질 로고 로더.
//

import SwiftUI


/// 메인 앱(LiveActivityService)이 App Group에 저장해둔 고화질 로고(180×180 PNG)를 읽는다.
/// ActivityKit attributes는 4KB 제한 때문에 저화질 썸네일만 담을 수 있으므로
/// 파일이 있으면 이쪽을 우선 사용한다. 파일명 규칙은 메인 앱과 동일해야 한다.
func sharedHiResLogo(teamCode: String) -> UIImage? {
    guard let base = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SharedDataService.appGroupId) else { return nil }
    let safe = teamCode
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    let url = base.appendingPathComponent("LiveActivityLogos/\(safe).png")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
}
