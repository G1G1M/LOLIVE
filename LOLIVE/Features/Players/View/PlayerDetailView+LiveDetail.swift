//
//  PlayerDetailView+LiveDetail.swift
//  LOLIVE
//
//  라이브 스탯 피드 `details`로 채우는 카드 — 아이템 빌드, 스킬 순서,
//  킬 관여율·딜 비중, 시야, 현재 전투 스탯.
//
//  [언제 부르나] 선수 행을 탭해 이 화면에 들어왔을 때 1회만. 경기 상세 화면의
//  5초 폴링에는 얹지 않는다 — 피드 프레임이 어차피 10초 단위라 폴링 부하만 2배가 된다.
//
//  [어느 시점을 부르나] 이미 화면에 띄운 window와 같은 순간(`lastFrameTimestamp`).
//  startingTime 없이 부르면 게임 초반(레벨 1, 아이템 없음) 프레임이 와서 쓸모가 없다.
//

import SwiftUI

extension PlayerDetailView {

    /// 이 선수가 뛴 게임 중 가장 최근 것에서, 화면에 보여준 window와 같은 시점의 상세를 가져온다.
    func loadLiveDetail() async {
        guard liveDetail == nil, !isLoadingLiveDetail else { return }

        let playable = games.filter { $0.state.isPlayable }
        guard let game = playable.last,
              let window = gameWindows[game.gameId],
              let capturedAt = window.lastFrameTimestamp,
              let me = (window.bluePlayers + window.redPlayers)
                  .first(where: { $0.summonerName == summonerName })
        else { return }

        isLoadingLiveDetail = true
        defer { isLoadingLiveDetail = false }

        let detail = try? await LiveStatsService()
            .fetchPlayerDetails(gameId: game.gameId, startingTime: capturedAt)
        liveDetail = detail?.player(me.participantId)
    }

    // MARK: - 카드

    @ViewBuilder
    var liveDetailCard: some View {
        if let detail = liveDetail {
            VStack(alignment: .leading, spacing: 0) {
                Text("최근 세트 상세")
                    .font(.headline)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

                buildSection(detail)
                Divider().padding(.horizontal, 16)
                contributionSection(detail)
                Divider().padding(.horizontal, 16)
                combatSection(detail)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: 빌드

    private func buildSection(_ detail: PlayerLiveDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ItemRowView(itemIds: detail.items)

            if !detail.abilities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("스킬 순서")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(detail.abilities.joined(separator: " › "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    // MARK: 기여도·시야

    private func contributionSection(_ detail: PlayerLiveDetail) -> some View {
        HStack(spacing: 0) {
            metric(percent(detail.killParticipation), "킬 관여")
            Divider().frame(height: 40)
            metric(percent(detail.championDamageShare), "딜 비중")
            Divider().frame(height: 40)
            metric("\(detail.wardsPlaced)", "와드 설치")
            Divider().frame(height: 40)
            metric("\(detail.wardsDestroyed)", "와드 제거")
        }
        .padding(.vertical, 10)
    }

    // MARK: 전투 스탯

    private func combatSection(_ detail: PlayerLiveDetail) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                metric("\(detail.attackDamage)", "공격력")
                Divider().frame(height: 40)
                metric("\(detail.abilityPower)", "주문력")
                Divider().frame(height: 40)
                metric("\(detail.attackSpeed)", "공격속도")
            }
            HStack(spacing: 0) {
                metric("\(detail.armor)", "방어력")
                Divider().frame(height: 40)
                metric("\(detail.magicResistance)", "마법저항")
                Divider().frame(height: 40)
                metric(percent(detail.criticalChance), "치명타")
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: 공통

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
