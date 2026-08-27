//
//  LiveStatsService+Detail.swift
//  LOLIVE
//
//  라이브 스탯 피드의 `details` 엔드포인트 — 선수별 빌드·기여도·시야·전투 스탯.
//
//  window와 달리 화면에서 항상 필요한 값이 아니라서, 선수 행을 탭해 상세 시트를
//  열 때만 호출한다(폴링 부하를 2배로 늘리지 않기 위함).
//

import Foundation

extension LiveStatsService {

    /// 특정 시점의 선수별 상세를 가져온다.
    /// - Parameter startingTime: 없으면 게임 초반 프레임이 온다(피드 특성). 진행 중인
    ///   경기는 "지금"보다 3분 25초 이상 과거를 넣어야 한다 — 그보다 최신은 400을 준다.
    func fetchPlayerDetails(gameId: String, startingTime: Date? = nil) async throws -> GameLiveDetail {
        var components = URLComponents(string: "\(detailBaseURL)/details/\(gameId)")
        if let startingTime {
            components?.queryItems = [
                URLQueryItem(name: "startingTime",
                             value: Self.feedTimestamp.string(from: Self.alignedToTenSeconds(startingTime)))
            ]
        }
        guard let url = components?.url else { throw APIError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(URLError(.badServerResponse))
        }
        // 204 = 그 시각에 프레임이 없음(경기 시작 전이거나 이미 끝난 뒤)
        guard (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw APIError.requestFailed(statusCode: http.statusCode)
        }

        return try decodeDetails(data, gameId: gameId)
    }

    /// 네트워크와 분리된 디코딩 — 실측 픽스처로 테스트에서 직접 호출한다.
    func decodeDetails(_ data: Data, gameId: String) throws -> GameLiveDetail {
        do {
            let response = try JSONDecoder().decode(DetailsFeedResponse.self, from: data)
            guard let frame = response.frames.last else {
                return GameLiveDetail(gameId: gameId, capturedAt: nil, players: [])
            }
            return GameLiveDetail(
                gameId: gameId,
                capturedAt: Self.feedTimestamp.date(from: frame.rfc460Timestamp),
                players: frame.participants.map(Self.map)
            )
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    // MARK: - DTO

    struct DetailsFeedResponse: Decodable {
        let frames: [Frame]

        struct Frame: Decodable {
            let rfc460Timestamp: String
            let participants: [Participant]
        }

        struct Participant: Decodable {
            let participantId: Int
            let level: Int
            let kills: Int
            let deaths: Int
            let assists: Int
            let totalGoldEarned: Int
            let creepScore: Int
            let killParticipation: Double
            let championDamageShare: Double
            let wardsPlaced: Int
            let wardsDestroyed: Int
            let attackDamage: Int
            let abilityPower: Int
            let criticalChance: Double
            let attackSpeed: Int
            let lifeSteal: Double
            let armor: Int
            let magicResistance: Int
            let tenacity: Double
            let items: [Int]
            let perkMetadata: PerkMetadata?
            let abilities: [String]
        }

        struct PerkMetadata: Decodable {
            let styleId: Int
            let subStyleId: Int
            let perks: [Int]
        }
    }

    private static func map(_ p: DetailsFeedResponse.Participant) -> PlayerLiveDetail {
        PlayerLiveDetail(
            participantId: p.participantId,
            level: p.level,
            kills: p.kills,
            deaths: p.deaths,
            assists: p.assists,
            totalGoldEarned: p.totalGoldEarned,
            creepScore: p.creepScore,
            killParticipation: p.killParticipation,
            championDamageShare: p.championDamageShare,
            wardsPlaced: p.wardsPlaced,
            wardsDestroyed: p.wardsDestroyed,
            attackDamage: p.attackDamage,
            abilityPower: p.abilityPower,
            armor: p.armor,
            magicResistance: p.magicResistance,
            attackSpeed: p.attackSpeed,
            criticalChance: p.criticalChance,
            lifeSteal: p.lifeSteal,
            tenacity: p.tenacity,
            items: p.items.filter { $0 > 0 },   // 빈 슬롯은 0으로 온다
            perkStyleId: p.perkMetadata?.styleId,
            perkSubStyleId: p.perkMetadata?.subStyleId,
            perks: p.perkMetadata?.perks ?? [],
            abilities: p.abilities
        )
    }
}
