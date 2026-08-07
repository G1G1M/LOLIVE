//
//  OnboardingView.swift
//  LOLIVE
//
//  [파일 구조]
//    - OnboardingView.swift               코어(화면 골격, 웰컴 페이지) + 공용 헬퍼
//    - OnboardingLoader.swift              실제 경기 데이터 로딩 로직
//    - OnboardingView+TodayMockup.swift    "오늘의 경기" 페이지 목업
//    - OnboardingView+StatsMockup.swift    "경기 상세 통계" 페이지 목업
//    - OnboardingView+FavoritesMockup.swift "즐겨찾기" 페이지 목업
//
//  Extension에서 접근해야 하므로 loader는 internal로 선언되어 있다.
//

import SwiftUI

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentPage = 0
    @State var loader = OnboardingLoader()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    todayPage.tag(1)
                    statsPage.tag(2)
                    favoritesPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Group {
                    if #available(iOS 26.0, *) {
                        Button {
                            if currentPage < 3 {
                                withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
                            } else {
                                onComplete()
                            }
                        } label: {
                            Text(currentPage < 3 ? "다음" : "시작하기")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                    } else {
                        Button {
                            if currentPage < 3 {
                                withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
                            } else {
                                onComplete()
                            }
                        } label: {
                            Text(currentPage < 3 ? "다음" : "시작하기")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: currentPage)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
        .task { await loader.load() }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        pageShell(
            mockup: welcomeMockup,
            title: "LOLIVE에 오신 것을 환영합니다",
            description: "LoL 이스포츠의 모든 경기 정보를\n한 앱에서 편리하게 확인하세요"
        )
    }

    private var todayPage: some View {
        pageShell(
            mockup: todayMockup,
            title: "오늘의 경기",
            description: "라이브 경기와 예정된 경기를\n실시간으로 확인하세요"
        )
    }

    private var statsPage: some View {
        pageShell(
            mockup: statsMockup,
            title: "경기 상세 통계",
            description: "챔피언 픽/밴부터\n선수별 실시간 스탯까지 한눈에"
        )
    }

    private var favoritesPage: some View {
        pageShell(
            mockup: favoritesMockup,
            title: "즐겨찾기",
            description: "좋아하는 팀과 선수를 즐겨찾기에 추가해\n빠르게 확인하세요"
        )
    }

    // MARK: - Shell

    private func pageShell(mockup: some View, title: String, description: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            mockup.padding(.horizontal, 24)
            VStack(spacing: 10) {
                Text(title)
                    .font(.title3).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Mockup: Welcome

    private var welcomeMockup: some View {
        VStack(spacing: 20) {
            Image("AppIconImage")
                .resizable()
                .interpolation(.high)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .yellow.opacity(0.5), radius: 24)

            HStack(spacing: 8) {
                ForEach(["LCK", "LPL", "LEC", "LCS"], id: \.self) { tag in
                    Text(tag)
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.15))
                        .foregroundStyle(.yellow)
                        .clipShape(Capsule())
                }
            }

            Text("실시간 경기 · 통계 · 선수 정보")
                .font(.caption).foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.yellow.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Helpers

    /// 통계/즐겨찾기 목업(다른 파일)에서도 쓰는 포지션 라벨이라 internal로 유지.
    func roleLabel(_ role: String) -> String { RoleStyle.label(role) }
}

#Preview {
    OnboardingView(onComplete: {})
}
