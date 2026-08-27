//
//  TodayViewModel+Filters.swift
//  LOLIVE
//
//  "즐겨찾기만 보기" 필터. Today 화면의 4개 목록(라이브/오늘/예정/완료)에 같은 규칙을 적용한다.
//

import Foundation

extension TodayViewModel {

    var hasFavoriteTeams: Bool { !favoritedTeams.isEmpty }

    var filteredLiveMatches: [LiveMatch] {
        guard showFavoritesOnly else { return liveMatches }
        return liveMatches.filter { isFavorited($0.match) }
    }

    var filteredTodayMatches: [Match] {
        guard showFavoritesOnly else { return todayMatches }
        return todayMatches.filter { isFavorited($0) }
    }

    var filteredUpcomingMatches: [Match] {
        guard showFavoritesOnly else { return upcomingMatches }
        return upcomingMatches.filter { isFavorited($0) }
    }

    var filteredCompletedMatches: [Match] {
        guard showFavoritesOnly else { return completedMatches }
        return completedMatches.filter { isFavorited($0) }
    }

    var displayedCompletedMatches: [Match] {
        let all = filteredCompletedMatches
        return showAllCompleted ? all : Array(all.prefix(completedMatchesLimit))
    }

    var hasMoreCompleted: Bool {
        !showAllCompleted && filteredCompletedMatches.count > completedMatchesLimit
    }

    var isFavoritesFilterEmpty: Bool {
        showFavoritesOnly &&
        filteredLiveMatches.isEmpty &&
        filteredTodayMatches.isEmpty &&
        filteredUpcomingMatches.isEmpty &&
        filteredCompletedMatches.isEmpty
    }


    func isFavorited(_ match: Match) -> Bool {
        FavoritedTeamRef.matches(favoritedTeams, team: match.teamA, league: match.league) ||
        FavoritedTeamRef.matches(favoritedTeams, team: match.teamB, league: match.league)
    }

    func favoriteTeamCode(for match: Match) -> String? {
        if FavoritedTeamRef.matches(favoritedTeams, team: match.teamA, league: match.league) {
            return match.teamA.code
        }
        if FavoritedTeamRef.matches(favoritedTeams, team: match.teamB, league: match.league) {
            return match.teamB.code
        }
        return nil
    }
}
