//
//  LiveMatch.swift
//  LOLIVE
//

import Foundation

struct LiveMatch: Codable, Identifiable, Hashable {
    var id: String { match.id }
    let match: Match
    let currentSet: Int
    let lastUpdated: Date
    /// 현재 진행 중인 게임(세트)의 esports game ID — 라이브 스탯 피드(feed.lolesports.com) 조회용
    let currentGameId: String?
}
