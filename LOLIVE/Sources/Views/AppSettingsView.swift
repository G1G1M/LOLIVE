//
//  AppSettingsView.swift
//  LOLIVE
//

import SwiftUI

struct AppSettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    #if DEBUG
    // 테스트 Live Activity 상태 (DEBUG 전용)
    @State private var testActivityRunning = false
    @State private var testScoreA = 0
    @State private var testScoreB = 0

    /// 알림 테스트용 더미 경기 (T1 vs Gen.G) — 실제 API 없이 알림 문구/동작 확인용
    private var testMatch: Match {
        Match(
            id: "lolive_test_match",
            league: League(id: "test_league", slug: "lck", name: "LCK", region: "KOREA", imageURL: nil),
            teamA: Team(id: "T1", name: "T1", code: "T1", imageURL: nil),
            teamB: Team(id: "GEN", name: "Gen.G", code: "GEN", imageURL: nil),
            scoreA: testScoreA, scoreB: testScoreB,
            startTime: Date(), state: .inProgress
        )
    }
    #endif

    var body: some View {
        List {
            #if DEBUG
            // MARK: - 테스트 (DEBUG 빌드에서만 표시)
            Section {
                Button {
                    Task { await MatchNotificationService.shared.sendTestNotification() }
                } label: {
                    Label("테스트 알림 (5초 후 발송)", systemImage: "bell.badge")
                }

                Button {
                    Task {
                        await MatchNotificationService.shared.sendMatchStartNotification(
                            for: testMatch, favoriteTeamCode: "T1"
                        )
                    }
                } label: {
                    Label("테스트: 경기 시작 알림", systemImage: "bell.badge")
                }

                Button {
                    Task {
                        await MatchNotificationService.shared.sendResultNotification(
                            for: testMatch, favoriteTeamCode: "T1"
                        )
                    }
                } label: {
                    Label("테스트: 경기 종료 알림", systemImage: "bell.badge")
                }

                if !testActivityRunning {
                    Button {
                        Task {
                            let ok = await LiveActivityService.shared.startTestActivity()
                            testActivityRunning = ok
                            testScoreA = 0; testScoreB = 0
                        }
                    } label: {
                        Label("Live Activity 시작 (T1 vs Gen.G)", systemImage: "play.circle")
                    }
                } else {
                    Button {
                        Task {
                            // 번갈아 한 세트씩 승리하는 시나리오 시뮬레이션
                            let endedSet = testScoreA + testScoreB + 1
                            if testScoreA <= testScoreB { testScoreA += 1 } else { testScoreB += 1 }
                            let newSet = testScoreA + testScoreB + 1
                            await LiveActivityService.shared.updateTestActivity(
                                scoreA: testScoreA, scoreB: testScoreB,
                                currentGame: newSet
                            )
                            // 실제 폴링과 동일한 순서: 세트 종료 알림 → 다음 세트 시작 알림
                            await MatchNotificationService.shared.sendSetEndNotification(
                                for: testMatch, favoriteTeamCode: "T1", endedSet: endedSet
                            )
                            await MatchNotificationService.shared.sendSetStartNotification(
                                for: testMatch, favoriteTeamCode: "T1", newSet: newSet
                            )
                        }
                    } label: {
                        Label("스코어 업데이트 (\(testScoreA):\(testScoreB) → 다음 세트)",
                              systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        Task {
                            await LiveActivityService.shared.endTestActivity()
                            testActivityRunning = false
                        }
                    } label: {
                        Label("Live Activity 종료", systemImage: "stop.circle")
                    }
                }
            } header: {
                Text("테스트 (DEBUG 전용)")
            } footer: {
                Text("알림: 버튼을 누르고 5초 안에 잠금화면으로 이동하면 잠금화면 알림도 확인할 수 있습니다. 경기 시작/종료 알림은 1초 후 바로 발송됩니다.\nLive Activity를 먼저 시작한 뒤 '스코어 업데이트'를 누르면 세트 종료/시작 알림과 다이나믹 아일랜드 배너를 동시에 확인할 수 있습니다. 이 섹션은 App Store 배포 빌드에는 표시되지 않습니다.")
            }
            .onAppear {
                testActivityRunning = LiveActivityService.shared.isTestActivityRunning
            }
            #endif

            // MARK: - 정보
            Section("정보") {
                NavigationLink(destination: LegalTextView(title: "이용약관", content: termsOfService)) {
                    Label("이용약관", systemImage: "doc.text")
                }
                NavigationLink(destination: LegalTextView(title: "개인정보처리방침", content: privacyPolicy)) {
                    Label("개인정보처리방침", systemImage: "lock.shield")
                }
                NavigationLink(destination: LegalTextView(title: "앱 사용 설명서", content: userGuide)) {
                    Label("앱 사용 설명서", systemImage: "questionmark.circle")
                }
            }

            // MARK: - 앱 정보
            Section("앱 정보") {
                HStack {
                    Text("버전")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("개발자")
                    Spacer()
                    Text("G1G1E")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - 법적 고지
            Section {
                Text("LOLIVE는 Riot Games의 공식 앱이 아닌 팬 제작 앱입니다. League of Legends 및 관련 상표는 Riot Games, Inc.의 재산입니다.\n\nThis app is not affiliated with or endorsed by Riot Games. League of Legends and all related trademarks are properties of Riot Games, Inc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("앱 설정")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Legal Text View

struct LegalTextView: View {
    let title: String
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Content

private let termsOfService = """
LOLIVE 이용약관

제1조 (목적)
본 약관은 LOLIVE 애플리케이션(이하 "앱")의 이용 조건 및 절차, 이용자와 운영자의 권리·의무 및 책임사항을 규정함을 목적으로 합니다.

제2조 (서비스 제공)
앱은 리그 오브 레전드 e스포츠 경기 일정, 순위, 선수 정보 등을 제공합니다. 경기 데이터는 Riot Games 비공식 API를 통해 수집되며, 정확성을 보장하지 않습니다.

제3조 (이용자 의무)
이용자는 앱을 법령 및 본 약관에 따라 이용해야 합니다. 앱의 정상적인 운영을 방해하는 행위를 해서는 안 됩니다.

제4조 (서비스 변경 및 중단)
운영자는 서비스 내용을 변경하거나 중단할 수 있으며, 이에 대해 이용자에게 별도의 보상을 하지 않습니다.

제5조 (면책사항)
앱이 제공하는 정보는 참고용이며, 정보의 정확성·완전성에 대해 보증하지 않습니다. 이용자가 앱의 정보를 이용하여 발생한 손해에 대해 운영자는 책임을 지지 않습니다.

제6조 (준거법 및 관할법원)
본 약관은 대한민국 법률에 따라 해석되며, 분쟁 발생 시 서울중앙지방법원을 전속 관할법원으로 합니다.

---

법적 고지 / Legal Notice

LOLIVE는 Riot Games의 공식 앱이 아닌 팬 제작 앱입니다. League of Legends 및 관련 상표는 Riot Games, Inc.의 재산입니다.

This app is not affiliated with or endorsed by Riot Games. League of Legends and all related trademarks are properties of Riot Games, Inc.
"""

private let privacyPolicy = """
LOLIVE 개인정보처리방침

1. 수집하는 개인정보 항목
앱은 별도의 개인정보를 수집하지 않습니다. 알림 설정, 즐겨찾기 등의 정보는 사용자의 기기에만 저장됩니다.

2. 개인정보의 이용 목적
수집된 정보는 앱 기능 제공(경기 알림, 즐겨찾기 팀 표시)에만 사용됩니다.

3. 개인정보의 보유 및 이용 기간
앱 삭제 시 기기에 저장된 모든 데이터가 삭제됩니다.

4. 개인정보의 제3자 제공
앱은 사용자 정보를 제3자에게 제공하지 않습니다.

5. 사용하는 외부 서비스
- Riot Games Esports API: 경기 일정 및 결과 데이터 제공
- Leaguepedia API: 경기 상세 정보 제공

6. 문의처
개인정보 관련 문의는 앱 스토어 리뷰 또는 개발자 이메일로 연락해 주세요.
"""

private let userGuide = """
LOLIVE 앱 사용 설명서

📅 오늘의 경기 (Today)
• 오늘 예정된 경기, 진행 중인 LIVE 경기, 완료된 경기를 한눈에 확인할 수 있습니다.
• 즐겨찾기 필터를 사용하면 관심 팀의 경기만 볼 수 있습니다.
• 경기 카드를 탭하면 상세 정보(밴픽, 인게임 스탯)를 볼 수 있습니다.

🏆 순위 (Standings)
• LCK, LPL, LEC 등 주요 리그별 팀 순위를 확인할 수 있습니다.
• 승/패와 세트 득실차로 정확한 순위를 표시합니다.
• 팀 이름을 탭하면 팀 상세 정보와 선수 로스터를 확인할 수 있습니다.

⭐ 즐겨찾기 (Favorites)
• 팀이나 선수를 즐겨찾기에 추가하면 경기 알림을 받을 수 있습니다.
• 팀을 길게 누르면 대표 팀으로 설정할 수 있습니다.

🔔 알림 설정
• 경기 시작 1시간 전, 30분 전, 15분 전, 5분 전 중 원하는 시간에 알림을 받을 수 있습니다.
• 알림을 받으려면 즐겨찾기에 팀을 추가하고, 기기의 알림 권한을 허용해야 합니다.

🔍 검색 (Search)
• 팀이나 선수 이름으로 검색할 수 있습니다.

💡 팁
• 오늘의 경기 화면을 아래로 당기면 새로 고침됩니다.
• LIVE 경기는 5초마다 자동으로 업데이트됩니다.
"""

#Preview {
    NavigationStack {
        AppSettingsView()
    }
    .preferredColorScheme(.dark)
}
