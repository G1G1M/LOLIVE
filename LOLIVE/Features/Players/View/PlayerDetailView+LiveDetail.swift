//
//  PlayerDetailView+LiveDetail.swift
//  LOLIVE
//
//  세트별 "맞라이너 대결" 카드. 세트 탭으로 G1/G2/… 을 오갈 수 있고,
//  아이템·룬·스킬 순서는 기본으로 접혀 있다.
//
//  [왜 이 배치인가] 카드를 열고 가장 먼저 궁금한 건 "이 선수가 라인전에서 이겼나"다.
//  그건 맞라이너와 나란히 놓아야만 답할 수 있다 — "공격력 124"는 상대가 217이었다는 걸
//  알아야 읽힌다. 빌드는 궁금해진 다음에 여는 정보라 접어둔다.
//

import SwiftUI

extension PlayerDetailView {

    @ViewBuilder
    var liveDetailCard: some View {
        if liveVM.games.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                liveHeader
                if liveVM.games.count > 1 {
                    liveGamePicker
                }
                Divider().padding(.horizontal, 16)
                liveBody
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .task(id: liveVM.selectedGameId) { await liveVM.loadSelected() }
        }
    }

    // MARK: - 헤더 · 세트 탭

    private var liveHeader: some View {
        HStack {
            Text("세트 상세")
                .font(.headline)
            Spacer()
            if let matchup = liveVM.selectedMatchup {
                Text(RoleStyle.label(matchup.role))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    /// 경기 상세의 세트 선택 칩과 같은 생김새 — 같은 동작엔 같은 모양을 쓴다.
    private var liveGamePicker: some View {
        HStack(spacing: 0) {
            ForEach(liveVM.games) { game in
                let isSelected = liveVM.selectedGameId == game.gameId
                Button {
                    liveVM.select(game.gameId)
                } label: {
                    Text("G\(game.number)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color(.label))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    // MARK: - 본문

    @ViewBuilder
    private var liveBody: some View {
        if let matchup = liveVM.selectedMatchup {
            VStack(alignment: .leading, spacing: 0) {
                matchupHeader(matchup)
                Divider().padding(.horizontal, 16)
                comparisonRows(matchup)
                Divider().padding(.horizontal, 16)
                buildSection(matchup.me.detail)
            }
        } else if liveVM.isLoadingSelected {
            LoadingView("세트 상세 불러오는 중...")
                .frame(height: 120)
        } else if liveVM.selectedFailure == .fetchFailed {
            // 실패를 감추지 않는다 — 안 보이는 것과 데이터가 없는 것은 다르다.
            VStack(spacing: 10) {
                Text("세트 상세를 불러오지 못했습니다")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("다시 시도") { Task { await liveVM.retrySelected() } }
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        } else {
            Text("이 세트는 상세 기록이 없습니다")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
        }
    }

    // MARK: - 대결 헤더

    private func matchupHeader(_ m: LaneMatchup) -> some View {
        HStack(spacing: 10) {
            sideLabel(champion: m.me.championId, name: m.me.summonerName,
                      isBlue: m.me.isBlue, alignment: .leading)

            if let diff = m.goldDifference {
                let ahead = diff >= 0
                VStack(spacing: 0) {
                    Text("\(ahead ? "+" : "-")\(formatGold(abs(diff)))")
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(ahead ? Color.blue : Color.red)
                    Text("골드 격차")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                .fixedSize()
            } else {
                Text("vs").font(.caption2).foregroundStyle(.tertiary)
            }

            if let opponent = m.opponent {
                sideLabel(champion: opponent.championId, name: opponent.summonerName,
                          isBlue: opponent.isBlue, alignment: .trailing)
            } else {
                Text("상대 기록 없음")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private func sideLabel(champion: String, name: String,
                           isBlue: Bool, alignment: HorizontalAlignment) -> some View {
        let isLeading = alignment == .leading
        return HStack(spacing: 8) {
            if !isLeading { Spacer(minLength: 0) }
            if isLeading { ChampionImageView(championId: champion, size: 32) }
            VStack(alignment: alignment, spacing: 1) {
                Text(champion)
                    .font(.caption).fontWeight(.bold).lineLimit(1)
                Text(name)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            if !isLeading { ChampionImageView(championId: champion, size: 32) }
            if isLeading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
    }

    // MARK: - 비교 행

    private func comparisonRows(_ m: LaneMatchup) -> some View {
        let me = m.me.detail
        let op = m.opponent?.detail

        return VStack(spacing: 9) {
            compareRow("KDA", left: me.kda, right: op?.kda ?? "-",
                       leftValue: me.kdaScore, rightValue: op?.kdaScore ?? 0, isBlue: m.isBlueSide)
            compareRow("킬 관여", left: percent(me.killParticipation), right: op.map { percent($0.killParticipation) } ?? "-",
                       leftValue: me.killParticipation, rightValue: op?.killParticipation ?? 0, isBlue: m.isBlueSide)
            compareRow("딜 비중", left: percent(me.championDamageShare), right: op.map { percent($0.championDamageShare) } ?? "-",
                       leftValue: me.championDamageShare, rightValue: op?.championDamageShare ?? 0, isBlue: m.isBlueSide,
                       footnote: m.showsDamageShareRank ? "팀 내 \(m.damageShareRank)위" : nil)
            compareRow("CS", left: "\(me.creepScore)", right: op.map { "\($0.creepScore)" } ?? "-",
                       leftValue: Double(me.creepScore), rightValue: Double(op?.creepScore ?? 0), isBlue: m.isBlueSide)
            compareRow("골드", left: formatGold(me.totalGoldEarned), right: op.map { formatGold($0.totalGoldEarned) } ?? "-",
                       leftValue: Double(me.totalGoldEarned), rightValue: Double(op?.totalGoldEarned ?? 0), isBlue: m.isBlueSide)
            compareRow("방어력", left: "\(me.armor)", right: op.map { "\($0.armor)" } ?? "-",
                       leftValue: Double(me.armor), rightValue: Double(op?.armor ?? 0), isBlue: m.isBlueSide)
            compareRow("마법저항", left: "\(me.magicResistance)", right: op.map { "\($0.magicResistance)" } ?? "-",
                       leftValue: Double(me.magicResistance), rightValue: Double(op?.magicResistance ?? 0), isBlue: m.isBlueSide)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// 가운데 라벨을 축으로 좌우 막대가 갈라진다 — 숫자를 읽기 전에 형태로 먼저 보이게.
    private func compareRow(_ label: String, left: String, right: String,
                            leftValue: Double, rightValue: Double,
                            isBlue: Bool, footnote: String? = nil) -> some View {
        let total = leftValue + rightValue
        // 양쪽 다 0이면 반반으로 칠하지 않는다 — 비교할 게 없는데 비교한 것처럼 보인다.
        let hasData = total > 0
        let leftRatio = hasData ? leftValue / total : 0
        let myColor: Color = isBlue ? .blue : .red
        let theirColor: Color = isBlue ? .red : .blue

        return HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(left)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit().lineLimit(1)
                bar(ratio: leftRatio, color: myColor, alignment: .trailing, hasData: hasData)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text(right)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit().lineLimit(1)
                bar(ratio: hasData ? 1 - leftRatio : 0, color: theirColor, alignment: .leading, hasData: hasData)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func bar(ratio: Double, color: Color, alignment: Alignment, hasData: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: alignment) {
                Capsule().fill(Color(.tertiarySystemFill))
                if hasData {
                    Capsule().fill(color)
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
        }
        .frame(height: 5)
    }

    // MARK: - 빌드 (접힘)

    @ViewBuilder
    private func buildSection(_ detail: PlayerLiveDetail) -> some View {
        DisclosureGroup(isExpanded: $isBuildExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                ItemRowView(itemIds: detail.items)

                if !detail.abilities.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("스킬 마스터 순서")
                            .font(.caption2).foregroundStyle(.secondary)
                        SkillOrderGrid(abilities: detail.abilities)
                    }
                }

                HStack(spacing: 0) {
                    miniMetric("\(detail.wardsPlaced)", "와드 설치")
                    Divider().frame(height: 32)
                    miniMetric("\(detail.wardsDestroyed)", "와드 제거")
                    Divider().frame(height: 32)
                    miniMetric("\(detail.attackDamage)", "공격력")
                    Divider().frame(height: 32)
                    miniMetric("\(detail.abilityPower)", "주문력")
                }
            }
            .padding(.top, 12)
        } label: {
            Text("아이템 · 스킬 · 시야")
                .font(.subheadline).fontWeight(.medium)
        }
        .tint(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func miniMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - 스킬 순서 격자

/// 레벨 1~18을 가로로 놓고 그 레벨에 찍은 스킬을 칠한다.
/// 줄글("Q › W › E › …")은 두 줄로 감기면서 마스터 순서가 안 보인다.
struct SkillOrderGrid: View {
    let abilities: [String]
    private let keys = ["Q", "W", "E", "R"]
    private let maxLevel = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(keys, id: \.self) { key in
                HStack(spacing: 2) {
                    Text(key)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .leading)
                    ForEach(0..<maxLevel, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(key: key, level: level))
                            .frame(height: 12)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("스킬 순서 \(abilities.joined(separator: ", "))")
    }

    private func color(key: String, level: Int) -> Color {
        guard level < abilities.count, abilities[level].uppercased() == key else {
            return Color(.tertiarySystemFill)
        }
        return key == "R" ? .orange : .accentColor
    }
}
