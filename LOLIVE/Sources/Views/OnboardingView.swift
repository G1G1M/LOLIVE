//
//  OnboardingView.swift
//  LOLIVE
//

import SwiftUI

// MARK: - Data Loader

@Observable
@MainActor
final class OnboardingLoader {
    var match: Match?
    var gameWindow: GameWindow?
    var playerImageURLs: [Int: URL] = [:]   // participantId → 프로필 이미지 URL

    func load() async {
        let esports = RiotEsportsService()

        guard let leagues = try? await esports.fetchLeagues(),
              let lck = leagues.first(where: { $0.slug == "lck" }) else { return }

        guard let schedule = try? await esports.fetchSchedule(league: lck),
              let recentMatch = schedule.first(where: { $0.state == .completed }) else { return }
        match = recentMatch

        guard let detail = try? await esports.fetchEventDetails(matchId: recentMatch.id),
              let game = detail.games.first(where: { $0.state == .completed }) else { return }

        let cache = GameWindowCache.shared
        if let cached = await cache.window(for: game.gameId) {
            gameWindow = cached
        } else {
            let liveStats = LiveStatsService()
            for offset: Double in [75, 60, 45, 30] {
                let startTime = recentMatch.startTime.addingTimeInterval(offset * 60)
                if let w = try? await liveStats.fetchGameWindow(gameId: game.gameId, startingTime: startTime),
                   w.hasLiveStats {
                    gameWindow = w
                    await cache.save(w)
                    break
                }
            }
        }

        // 즐겨찾기 페이지용 선수 프로필 이미지 (각 팀 1명씩)
        guard let window = gameWindow else { return }
        let targets = [window.bluePlayers.first, window.redPlayers.first].compactMap { $0 }
        let leaguepedia = LeaguepediaService.shared
        var urls: [Int: URL] = [:]
        for player in targets {
            guard !Task.isCancelled else { break }
            if let url = await leaguepedia.fetchPlayerImageURL(summonerName: player.summonerName) {
                urls[player.participantId] = url
            }
        }
        playerImageURLs = urls
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentPage = 0
    @State private var loader = OnboardingLoader()

    private let accentColors: [Color] = [.yellow, .blue, .green, .orange]

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
                        .background(accentColors[currentPage])
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
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

    // MARK: - Mockup: Today

    private var todayMockup: some View {
        let teamA   = loader.match?.teamA
        let teamB   = loader.match?.teamB
        let scoreA  = loader.match?.scoreA ?? 0
        let scoreB  = loader.match?.scoreB ?? 0
        let wonA    = scoreA > scoreB
        let loaded  = loader.match != nil

        return VStack(spacing: 0) {
            // 헤더
            HStack {
                statusPill(text: "완료", color: .secondary)
                Spacer()
                Text(loader.match?.league.name ?? "LCK")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider().background(.white.opacity(0.08))

            // 팀 스코어
            HStack(alignment: .center, spacing: 0) {
                // 팀 A
                VStack(spacing: 8) {
                    CachedAsyncImage(url: URL(string: teamA?.imageURL ?? ""))
                        .frame(width: 52, height: 52)
                        .background(loaded ? Color.clear : Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(teamA?.code ?? "—")
                        .font(.subheadline)
                        .fontWeight(wonA ? .bold : .regular)
                        .foregroundStyle(wonA ? .white : .secondary)
                }
                .frame(maxWidth: .infinity)

                // 스코어
                HStack(spacing: 12) {
                    Text("\(scoreA)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(wonA ? .white : .white.opacity(0.35))
                    Text(":")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("\(scoreB)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(!wonA ? .white : .white.opacity(0.35))
                }
                .frame(width: 120)

                // 팀 B
                VStack(spacing: 8) {
                    CachedAsyncImage(url: URL(string: teamB?.imageURL ?? ""))
                        .frame(width: 52, height: 52)
                        .background(loaded ? Color.clear : Color.purple.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(teamB?.code ?? "—")
                        .font(.subheadline)
                        .fontWeight(!wonA ? .bold : .regular)
                        .foregroundStyle(!wonA ? .white : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 16)

            Divider().background(.white.opacity(0.08))

            // 하단 안내
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("경기 일정 및 결과를 한눈에")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.blue.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Mockup: Stats

    private var statsMockup: some View {
        let teamA    = loader.match?.teamA
        let teamB    = loader.match?.teamB
        let blue     = loader.gameWindow?.bluePlayers.prefix(2) ?? []
        let red      = loader.gameWindow?.redPlayers.prefix(2) ?? []
        let bStats   = loader.gameWindow?.blueTeamStats
        let rStats   = loader.gameWindow?.redTeamStats
        let hasData  = loader.gameWindow != nil

        return VStack(spacing: 0) {
            // 팀 헤더
            HStack {
                HStack(spacing: 6) {
                    CachedAsyncImage(url: URL(string: teamA?.imageURL ?? ""))
                        .frame(width: 20, height: 20)
                        .background(hasData ? Color.clear : Color.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(teamA?.code ?? "Blue")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.blue)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(teamB?.code ?? "Red")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.red)
                    CachedAsyncImage(url: URL(string: teamB?.imageURL ?? ""))
                        .frame(width: 20, height: 20)
                        .background(hasData ? Color.clear : Color.red.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.white.opacity(0.07))

            // 팀 스탯
            VStack(spacing: 0) {
                statsRow("킬",   l: "\(bStats?.totalKills ?? 0)",        r: "\(rStats?.totalKills ?? 0)")
                Divider().background(.white.opacity(0.07))
                statsRow("골드", l: goldStr(bStats?.totalGold ?? 0),     r: goldStr(rStats?.totalGold ?? 0))
                Divider().background(.white.opacity(0.07))
                statsRow("타워", l: "\(bStats?.towers ?? 0)",            r: "\(rStats?.towers ?? 0)")
            }

            Divider().background(.white.opacity(0.12))

            // 블루팀 선수
            if !blue.isEmpty {
                sideLabel("Blue", color: .blue)
                ForEach(Array(blue.enumerated()), id: \.element.id) { i, p in
                    playerRow(p, sideColor: .blue)
                    if i < blue.count - 1 { Divider().background(.white.opacity(0.06)).padding(.leading, 44) }
                }
            }

            // 레드팀 선수
            if !red.isEmpty {
                Divider().background(.white.opacity(0.12))
                sideLabel("Red", color: .red)
                ForEach(Array(red.enumerated()), id: \.element.id) { i, p in
                    playerRow(p, sideColor: .red)
                    if i < red.count - 1 { Divider().background(.white.opacity(0.06)).padding(.leading, 44) }
                }
            }

            // 로딩 중 플레이스홀더
            if !hasData {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("선수 데이터 불러오는 중...")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.green.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Mockup: Favorites

    private var favoritesMockup: some View {
        let teamA   = loader.match?.teamA
        let teamB   = loader.match?.teamB
        let players = [loader.gameWindow?.bluePlayers.first,
                       loader.gameWindow?.redPlayers.first].compactMap { $0 }

        return VStack(spacing: 0) {
            // 팀 즐겨찾기
            HStack {
                Text("팀").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            VStack(spacing: 1) {
                favTeamRow(team: teamA, fallbackCode: "T1",  fallbackName: "티원",  fallbackColor: .blue)
                favTeamRow(team: teamB, fallbackCode: "GEN", fallbackName: "젠지",  fallbackColor: .purple)
            }

            // 선수 즐겨찾기
            HStack {
                Text("선수").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            VStack(spacing: 1) {
                if players.isEmpty {
                    // 로딩 전 플레이스홀더
                    favPlayerRowStatic(color: .blue,  role: "MID", name: "Faker",  team: "T1")
                    favPlayerRowStatic(color: .green, role: "JGL", name: "Canyon", team: "GEN")
                } else {
                    ForEach(players, id: \.id) { player in
                        favPlayerRowLive(player: player)
                    }
                }
            }

            Spacer().frame(height: 14)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.orange.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Stats Sub-components

    private func sideLabel(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(color.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(color.opacity(0.07))
    }

    private func statsRow(_ label: String, l: String, r: String) -> some View {
        HStack {
            Text(l)
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .center)
            Text(r)
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 8)
    }

    private func playerRow(_ player: PlayerStats, sideColor: Color) -> some View {
        HStack(spacing: 8) {
            Text(roleLabel(player.role))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(sideColor.opacity(0.7))
                .frame(width: 24, alignment: .center)
            ChampionImageView(championId: player.championId, size: 24)
            Text(player.summonerName)
                .font(.caption).fontWeight(.medium).foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if player.hasStats {
                Text("\(player.kills)/\(player.deaths)/\(player.assists)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: - Favorites Sub-components

    private func favTeamRow(team: Team?, fallbackCode: String, fallbackName: String, fallbackColor: Color) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: team?.imageURL ?? ""))
                .frame(width: 36, height: 36)
                .background(team == nil ? fallbackColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(team?.name ?? fallbackName)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                    .lineLimit(1)
                Text(team?.code ?? fallbackCode)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.subheadline).foregroundStyle(.yellow)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
    }

    private func favPlayerRowLive(player: PlayerStats) -> some View {
        HStack(spacing: 12) {
            let profileURL = loader.playerImageURLs[player.participantId]
            if profileURL != nil {
                CachedAsyncImage(url: profileURL)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                ChampionImageView(championId: player.championId, size: 36)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.summonerName)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                Text(roleLabel(player.role))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.subheadline).foregroundStyle(.yellow)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
    }

    private func favPlayerRowStatic(color: Color, role: String, name: String, team: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                Text("\(team) · \(role)").font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "star.fill")
                .font(.subheadline).foregroundStyle(.yellow)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Helpers

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }

    private func goldStr(_ gold: Int) -> String {
        gold >= 1000 ? String(format: "%.1fk", Double(gold) / 1000) : "\(gold)"
    }

    private func roleLabel(_ role: String) -> String {
        switch role.lowercased() {
        case "top":     return "TOP"
        case "jungle":  return "JGL"
        case "mid":     return "MID"
        case "bottom":  return "BOT"
        case "support": return "SUP"
        default:        return String(role.prefix(3)).uppercased()
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
