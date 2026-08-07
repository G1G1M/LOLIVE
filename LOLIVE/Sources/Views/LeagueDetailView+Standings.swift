//
//  LeagueDetailView+Standings.swift
//  LOLIVE
//
//  리그 상세 화면의 순위 탭.
//  LCK처럼 그룹(Baron/Elder 등)이 있는 리그는 그룹별 블록으로 나눠 표시한다.
//

import SwiftUI

extension LeagueDetailView {

    // MARK: - 순위 탭

    var standingsContent: some View {
        let groups = viewModel.standingGroups
        return ScrollView {
            if viewModel.standings.isEmpty {
                EmptyStateView("순위 데이터가 없습니다")
                    .padding(16)
            } else if groups.isEmpty {
                // 그룹 없는 단일 순위표
                standingsBlock(standings: viewModel.standings, groupName: nil)
                    .padding(16)
            } else {
                // 그룹별 순위표 (그룹명 헤더 포함)
                VStack(spacing: 12) {
                    ForEach(groups, id: \.name) { group in
                        standingsBlock(standings: group.standings, groupName: group.name)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - 순위표 블록

    private func standingsBlock(standings: [Standing], groupName: String?) -> some View {
        VStack(spacing: 0) {
            if let name = groupName {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 14)
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider().padding(.horizontal, 16)
            }
            standingsHeader
            ForEach(standings) { standing in
                standingRow(standing)
                if standing.id != standings.last?.id {
                    Divider().padding(.leading, 72)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var standingsHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 32, alignment: .center)
                .foregroundStyle(.secondary)
            Text("팀")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Text("W")
                    .foregroundStyle(.blue)
                    .frame(width: 22, alignment: .center)
                Text("-")
                    .foregroundStyle(.secondary)
                    .frame(width: 10, alignment: .center)
                Text("L")
                    .foregroundStyle(.red)
                    .frame(width: 22, alignment: .center)
            }
            .frame(width: 54)
            Text("GD")
                .frame(width: 44, alignment: .center)
                .foregroundStyle(.secondary)
            Text("Win%")
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func standingRow(_ standing: Standing) -> some View {
        NavigationLink(value: standing.team) {
            HStack(spacing: 0) {
                Text("\(standing.rank)")
                    .font(.system(size: 14, weight: standing.rank <= 3 ? .bold : .regular))
                    .foregroundStyle(rankColor(standing.rank))
                    .frame(width: 32, alignment: .center)

                HStack(spacing: 10) {
                    CachedAsyncImage(url: URL(string: standing.team.imageURL ?? ""))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(standing.team.name)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(1)
                        Text(standing.team.code)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0) {
                    Text("\(standing.wins)")
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                        .frame(width: 22, alignment: .center)
                    Text("-")
                        .foregroundStyle(.secondary)
                        .frame(width: 10, alignment: .center)
                    Text("\(standing.losses)")
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .frame(width: 22, alignment: .center)
                }
                .font(.system(size: 13, weight: .medium))
                .frame(width: 54)

                Text(gdString(standing.gameDiff))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(.label))
                    .frame(width: 44, alignment: .center)

                Text(String(format: "%.0f%%", standing.winRate * 100))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(.label))
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 헬퍼

    /// 1~3위는 금/은/동 색상으로 강조
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.8, blue: 0.0)
        case 2: return Color(.systemGray)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return Color(.label)
        }
    }

    /// 득실차 문자열 (+5 / -3 / 0)
    private func gdString(_ gd: Int) -> String {
        gd > 0 ? "+\(gd)" : "\(gd)"
    }
}
