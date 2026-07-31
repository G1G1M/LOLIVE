//
//  LiveActivityService.swift
//  LOLIVE

import ActivityKit
import Foundation
import UIKit
import os

@MainActor
final class LiveActivityService {

    static let shared = LiveActivityService()
    private var activities: [String: Activity<MatchActivityAttributes>] = [:]
    private let logger = Logger(subsystem: "com.lolive", category: "LiveActivity")

    private init() {
        // 앱 재시작 시 ActivityKit에 살아있는 기존 Activity를 딕셔너리에 복원
        // → 없으면 동일 경기에 대해 Activity가 중복 생성됨
        for activity in Activity<MatchActivityAttributes>.activities {
            activities[activity.attributes.matchId] = activity
        }
    }

    // MARK: - Private

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
    private func saveHiResLogo(_ original: UIImage, teamCode: String) async {
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
    private func fetchThumbnail(urlString: String?, teamCode: String) async -> Data? {
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

    // MARK: - 테스트 (DEBUG 빌드 전용)

    #if DEBUG
    /// 테스트용 더미 경기 ID — 실제 경기 Activity와 충돌하지 않는 고정 값
    private static let testMatchId = "lolive_test_activity"

    /// 테스트 Activity가 실행 중인지 여부 (설정 화면 버튼 상태용)
    var isTestActivityRunning: Bool {
        activities[Self.testMatchId] != nil
    }

    /// 더미 경기(T1 vs Gen.G)로 Live Activity 즉시 시작.
    /// 실제 경기 시간과 무관하게 Dynamic Island / 잠금화면 표시를 확인할 수 있다.
    /// - Returns: 시작 성공 여부 (실패 시 설정 > 실시간 활동 비활성화가 원인일 가능성)
    @discardableResult
    func startTestActivity() async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.debug("⚠️ [LiveActivity 테스트] 비활성화됨 — 설정 > LOLIVE > 실시간 활동 확인")
            return false
        }
        guard activities[Self.testMatchId] == nil else { return true }  // 이미 실행 중

        // 실제 로고를 fetch해 위젯 이미지 표시까지 함께 검증
        async let thumbA = fetchThumbnail(
            urlString: "https://lol.fandom.com/wiki/Special:FilePath/T1logo_std.png",
            teamCode: "T1")
        async let thumbB = fetchThumbnail(
            urlString: "https://lol.fandom.com/wiki/Special:FilePath/Gen.Glogo_std.png",
            teamCode: "GEN")
        let (teamAData, teamBData) = await (thumbA, thumbB)

        let attrs = MatchActivityAttributes(
            matchId: Self.testMatchId,
            teamAName: "T1",
            teamACode: "T1",
            teamAImageURL: nil,
            teamAImageData: teamAData,
            teamBName: "Gen.G",
            teamBCode: "GEN",
            teamBImageURL: nil,
            teamBImageData: teamBData,
            leagueName: "LCK (테스트)"
        )
        let state = MatchActivityAttributes.ContentState(
            scoreA: 0, scoreB: 0, currentGame: 1, isLive: true
        )
        do {
            let activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            activities[Self.testMatchId] = activity
            logger.debug("✅ [LiveActivity 테스트] 시작 id=\(activity.id)")
            return true
        } catch {
            logger.debug("❌ [LiveActivity 테스트] 시작 실패: \(error)")
            return false
        }
    }

    /// 테스트 Activity의 스코어/세트 업데이트 — 실시간 갱신 동작 검증용.
    /// 세트 번호가 바뀌면 실제 syncActivities와 동일하게 배너+알림음을 함께 트리거한다.
    func updateTestActivity(scoreA: Int, scoreB: Int, currentGame: Int) async {
        guard let activity = activities[Self.testMatchId] else { return }
        let alert: AlertConfiguration? = activity.content.state.currentGame != currentGame
            ? AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: "Game \(currentGame) 시작"),
                body: LocalizedStringResource(stringLiteral: "T1 \(scoreA) - \(scoreB) GEN"),
                sound: .default
              )
            : nil
        let state = MatchActivityAttributes.ContentState(
            scoreA: scoreA, scoreB: scoreB, currentGame: currentGame, isLive: true
        )
        await activity.update(.init(state: state, staleDate: nil), alertConfiguration: alert)
        logger.debug("🔄 [LiveActivity 테스트] 업데이트 \(scoreA):\(scoreB) 세트\(currentGame)")
    }

    /// 테스트 Activity 즉시 종료.
    func endTestActivity() async {
        guard let activity = activities[Self.testMatchId] else { return }
        await activity.end(dismissalPolicy: .immediate)
        activities.removeValue(forKey: Self.testMatchId)
        logger.debug("🏁 [LiveActivity 테스트] 종료")
    }
    #endif

    // MARK: - Public

    /// 폴링 결과로 liveMatches가 갱신될 때마다 호출
    /// — 즐겨찾기 팀의 경기 Live Activity를 시작/업데이트/종료
    /// - overdueMatches: startTime 지났으나 API 미확인 경기 (예약 시각부터 pre-live Activity 표시)
    func syncActivities(_ liveMatches: [LiveMatch], overdueMatches: [Match] = [], favoritedTeamIds: Set<String>) async {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            #if DEBUG
            logger.debug("⚠️ [LiveActivity] 비활성화됨 — 설정 > LOLIVE > 실시간 활동에서 켜주세요")
            #endif
            return
        }

        let relevant = liveMatches.filter {
            favoritedTeamIds.contains($0.match.teamA.id) ||
            favoritedTeamIds.contains($0.match.teamB.id) ||
            favoritedTeamIds.contains($0.match.teamA.code) ||
            favoritedTeamIds.contains($0.match.teamB.code)
        }

        // 라이브 경기 + 예약 시각 지난 경기 모두 유지 (둘 다 아닌 경우에만 종료)
        let liveIds = Set(relevant.map { $0.match.id })
        let overdueIds = Set(overdueMatches.map { $0.id })
        let keepIds = liveIds.union(overdueIds)
        for (id, activity) in activities where !keepIds.contains(id) {
            await activity.end(dismissalPolicy: .immediate)
            activities.removeValue(forKey: id)
        }

        // 진행 중인 경기 시작 또는 업데이트
        for liveMatch in relevant {
            let state = MatchActivityAttributes.ContentState(
                scoreA: liveMatch.match.scoreA,
                scoreB: liveMatch.match.scoreB,
                currentGame: liveMatch.currentSet,
                isLive: true
            )

            if let activity = activities[liveMatch.match.id] {
                // 세트가 바뀐 경우에만 다이나믹 아일랜드/잠금화면에 배너+알림음 표시
                // (매 폴링마다 조용히 갱신되는 것과 구분 — 세트 종료라는 의미 있는 순간에만 알림)
                let alert: AlertConfiguration? = activity.content.state.currentGame != state.currentGame
                    ? AlertConfiguration(
                        title: LocalizedStringResource(stringLiteral: "Game \(state.currentGame) 시작"),
                        body: LocalizedStringResource(stringLiteral: "\(liveMatch.match.teamA.code) \(state.scoreA) - \(state.scoreB) \(liveMatch.match.teamB.code)"),
                        sound: .default
                      )
                    : nil
                await activity.update(.init(state: state, staleDate: nil), alertConfiguration: alert)
            } else {
                // 두 팀 썸네일을 병렬로 fetch
                async let thumbA = fetchThumbnail(urlString: liveMatch.match.teamA.imageURL, teamCode: liveMatch.match.teamA.code)
                async let thumbB = fetchThumbnail(urlString: liveMatch.match.teamB.imageURL, teamCode: liveMatch.match.teamB.code)
                let (teamAImageData, teamBImageData) = await (thumbA, thumbB)

                // teamAImageURL/teamBImageURL은 attributes에 담지 않는다 (4KB 예산 절약) —
                // 위젯은 어차피 App Group 고화질 파일 → 썸네일 데이터 순으로 우선 사용하고,
                // URL은 그 둘 다 없을 때만 쓰는 최후 폴백이라 생략해도 실사용에 영향 없다.
                let attrs = MatchActivityAttributes(
                    matchId: liveMatch.match.id,
                    teamAName: liveMatch.match.teamA.name,
                    teamACode: liveMatch.match.teamA.code,
                    teamAImageURL: nil,
                    teamAImageData: teamAImageData,
                    teamBName: liveMatch.match.teamB.name,
                    teamBCode: liveMatch.match.teamB.code,
                    teamBImageURL: nil,
                    teamBImageData: teamBImageData,
                    leagueName: liveMatch.match.league.name
                )
                do {
                    let activity = try Activity.request(
                        attributes: attrs,
                        content: .init(state: state, staleDate: nil),
                        pushType: nil
                    )
                    activities[liveMatch.match.id] = activity
                    #if DEBUG
                    logger.debug("✅ [LiveActivity] 시작: \(liveMatch.match.teamA.code) vs \(liveMatch.match.teamB.code) id=\(activity.id)")
                    logger.debug("   imgA=\(teamAImageData?.count ?? 0)B  imgB=\(teamBImageData?.count ?? 0)B")
                    #endif
                } catch {
                    #if DEBUG
                    logger.debug("❌ [LiveActivity] request 실패: \(error)")
                    #endif
                }
            }
        }

        // 예약 시각이 지났으나 API 미확인 경기 → pre-live Activity (isLive: false)
        for match in overdueMatches {
            guard activities[match.id] == nil else { continue }  // 이미 시작됨

            let state = MatchActivityAttributes.ContentState(
                scoreA: 0, scoreB: 0, currentGame: 1, isLive: false
            )
            async let thumbA = fetchThumbnail(urlString: match.teamA.imageURL, teamCode: match.teamA.code)
            async let thumbB = fetchThumbnail(urlString: match.teamB.imageURL, teamCode: match.teamB.code)
            let (teamAData, teamBData) = await (thumbA, thumbB)

            let attrs = MatchActivityAttributes(
                matchId: match.id,
                teamAName: match.teamA.name,
                teamACode: match.teamA.code,
                teamAImageURL: nil,
                teamAImageData: teamAData,
                teamBName: match.teamB.name,
                teamBCode: match.teamB.code,
                teamBImageURL: nil,
                teamBImageData: teamBData,
                leagueName: match.league.name
            )
            do {
                let activity = try Activity.request(
                    attributes: attrs,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                activities[match.id] = activity
                #if DEBUG
                logger.debug("⏰ [LiveActivity] 예약시작: \(match.teamA.code) vs \(match.teamB.code) id=\(activity.id)")
                #endif
            } catch {
                #if DEBUG
                logger.debug("❌ [LiveActivity] 예약시작 실패: \(error)")
                #endif
            }
        }
    }
}
