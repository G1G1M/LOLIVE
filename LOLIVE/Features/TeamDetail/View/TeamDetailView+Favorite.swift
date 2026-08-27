//
//  TeamDetailView+Favorite.swift
//  LOLIVE
//
//  팀 상세의 즐겨찾기 토글과, 즐겨찾기에 저장할 "홈 리그" 판별.
//

import SwiftUI
import SwiftData

extension TeamDetailView {

    func checkFavoriteStatus() {
        let id = team.id
        let descriptor = FetchDescriptor<FavoriteTeam>(predicate: #Predicate { $0.teamId == id })
        isFavorited = (try? modelContext.fetch(descriptor))?.isEmpty == false
    }

    func toggleFavorite() {
        let id = team.id
        let descriptor = FetchDescriptor<FavoriteTeam>(predicate: #Predicate { $0.teamId == id })
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            existing.forEach { modelContext.delete($0) }
            isFavorited = false
        } else {
            modelContext.insert(FavoriteTeam(team: team, league: resolvedHomeLeague))
            isFavorited = true
        }
    }

    // 국제 대회(MSI/Worlds)·국내 컵 대회(케스파컵 등) 컨텍스트에서 즐겨찾기 시 홈 리그로 저장.
    // 이런 대회는 팀의 정규 소속 리그가 아니라 별도로 열리는 대회라, 팀 상세 진입 시에도
    // 항상 홈 리그(LCK 등) 기준 선수단·최근경기·즐겨찾기 소속 리그를 사용해야 한다.
    var resolvedHomeLeague: League {
        guard Self.isSpecialTournament(league) else { return league }
        let allMatches = todayViewModel.completedMatches + todayViewModel.todayMatches + todayViewModel.upcomingMatches
        for match in allMatches {
            guard !Self.isSpecialTournament(match.league) else { continue }
            if match.teamA.code.uppercased() == team.code.uppercased() ||
               match.teamB.code.uppercased() == team.code.uppercased() {
                return match.league
            }
        }
        return league
    }

    /// 팀의 정규 소속 리그가 아니라 별도로 열리는 대회인지 판별.
    /// MSI/Worlds 같은 국제 대회뿐 아니라 케스파컵처럼 지역이 "한국"으로 찍히는
    /// 국내 컵 대회도 포함 — region만으로는 못 걸러서 이름/슬러그도 함께 확인한다.
    private static func isSpecialTournament(_ league: League) -> Bool {
        let name = league.name.lowercased()
        let slug = league.slug.lowercased()
        let region = league.region.lowercased()
        return name.contains("msi") || name.contains("worlds") || name.contains("월드") ||
               region.contains("international") || region.contains("국제") ||
               name.contains("kespa") || slug.contains("kespa")
    }
}
