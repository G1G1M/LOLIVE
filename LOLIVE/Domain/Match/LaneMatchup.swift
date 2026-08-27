//
//  LaneMatchup.swift
//  LOLIVE
//
//  선수 한 명의 세트 기록을 "같은 라인에서 맞붙은 상대"와 짝지어 놓은 것.
//
//  [왜 짝을 짓나] 라이브 피드가 주는 숫자는 혼자 놓으면 잘한 건지 알 수가 없다.
//  "공격력 124"는 맞라이너가 217이었다는 걸 알아야 읽히고, "방어력 247"은 상대가
//  85였다는 걸 알아야 탱커가 제 역할을 했다는 뜻이 된다. 그래서 화면에 넘기기 전에
//  여기서 미리 짝을 맞춘다.
//
//  [짝 규칙] 피드가 참가자마다 role("top"/"jungle"/"mid"/"bottom"/"support")을 그대로
//  주므로, 반대편에서 같은 role을 찾으면 된다 — 챔피언이나 좌표로 추측하지 않는다.
//

import Foundation

struct LaneMatchup {

    struct Side {
        let participantId: Int
        let summonerName: String
        let championId: String
        let isBlue: Bool
        let detail: PlayerLiveDetail
    }

    let gameNumber: Int
    /// 피드가 준 role 원문. 화면 표기는 RoleStyle이 맡는다.
    let role: String
    let me: Side
    /// 같은 role의 상대. 로스터가 어긋나 못 찾으면 nil — 그땐 비교 없이 내 값만 보여준다.
    let opponent: Side?

    /// 팀 안에서 내 딜 비중이 몇 번째인지(1이 가장 높음). 맞라이너 비교만으로는
    /// "우리 팀에서 몇 번째 딜러인가"가 안 보여서 한 줄로 덧붙인다.
    let damageShareRank: Int
    let teamSize: Int

    var isBlueSide: Bool { me.isBlue }

    /// 맞라이너와의 골드 격차. 상대가 없거나 양쪽 다 0이면 nil.
    ///
    /// [왜 승패 판정을 안 하나] 처음엔 골드·CS·딜 비중 중 둘 이상 앞서면 "앞섬"으로
    /// 표시했는데, 탱커는 그 셋이 원래 낮아서 오판이 났다 — Ornn이 5/1/18로 압도하고
    /// 팀이 그 세트를 이겼는데 "밀림"으로 뜨는 걸 실제로 확인했다. 한 시점의 스냅샷으로
    /// 라인전 승패를 단정하는 대신, 다투기 어려운 사실 하나만 보여준다.
    var goldDifference: Int? {
        guard let opponent else { return nil }
        let mine = me.detail.totalGoldEarned
        let theirs = opponent.detail.totalGoldEarned
        guard mine > 0 || theirs > 0 else { return nil }
        return mine - theirs
    }

    /// 팀 딜 비중이 전부 0이면(세트 시작 직후) 순위는 아무 뜻이 없다.
    var showsDamageShareRank: Bool { me.detail.championDamageShare > 0 }
}

extension LaneMatchup {

    /// window(누가 어느 라인인지)와 details(실제 수치)를 합쳐 한 선수의 대결 구도를 만든다.
    /// 둘 중 하나라도 이 선수를 모르면 nil.
    static func build(
        gameNumber: Int,
        window: GameWindow,
        detail: GameLiveDetail,
        summonerName: String
    ) -> LaneMatchup? {
        let blue = window.bluePlayers
        let red  = window.redPlayers

        guard let mePlayer = (blue + red).first(where: { $0.summonerName == summonerName }),
              let meDetail = detail.player(mePlayer.participantId)
        else { return nil }

        let meIsBlue = blue.contains { $0.participantId == mePlayer.participantId }
        let myTeam = meIsBlue ? blue : red
        let theirTeam = meIsBlue ? red : blue

        let me = Side(participantId: mePlayer.participantId,
                      summonerName: mePlayer.summonerName,
                      championId: mePlayer.championId,
                      isBlue: meIsBlue,
                      detail: meDetail)

        // 같은 role을 상대 팀에서 찾는다. 봇/서포터도 각자 같은 role끼리 맞춰지므로
        // 포지션마다 예외를 두지 않아도 된다.
        let opponent: Side? = theirTeam
            .first { $0.role.caseInsensitiveCompare(mePlayer.role) == .orderedSame }
            .flatMap { player in
                detail.player(player.participantId).map {
                    Side(participantId: player.participantId,
                         summonerName: player.summonerName,
                         championId: player.championId,
                         isBlue: !meIsBlue,
                         detail: $0)
                }
            }

        // 팀 내 딜 비중 순위 — 상세가 없는 팀원은 순위 계산에서 빠진다.
        let teamShares = myTeam.compactMap { detail.player($0.participantId)?.championDamageShare }
        let rank = teamShares.filter { $0 > meDetail.championDamageShare }.count + 1

        return LaneMatchup(
            gameNumber: gameNumber,
            role: mePlayer.role,
            me: me,
            opponent: opponent,
            damageShareRank: rank,
            teamSize: max(teamShares.count, 1)
        )
    }
}
