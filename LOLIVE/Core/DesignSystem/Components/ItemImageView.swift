//
//  ItemImageView.swift
//  LOLIVE
//
//  라이브 스탯 피드가 숫자 ID로만 주는 아이템을 아이콘으로 보여준다.
//  ChampionImageView와 같은 패턴(DDragon URL 해석 + CachedAsyncImage).
//

import SwiftUI

struct ItemImageView: View {
    let itemId: Int
    var size: CGFloat = 28

    @State private var imageURL: URL?

    var body: some View {
        CachedAsyncImage(url: imageURL)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .task(id: itemId) {
                imageURL = await DDragonService.shared.itemImageURL(for: itemId)
            }
    }
}

/// 인벤토리 한 줄. 빈 슬롯은 회색 칸으로 자리만 잡아 6칸 정렬이 흐트러지지 않게 한다.
struct ItemRowView: View {
    let itemIds: [Int]
    var size: CGFloat = 28
    var slots: Int = 6

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<slots, id: \.self) { index in
                if index < itemIds.count {
                    ItemImageView(itemId: itemIds[index], size: size)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.18)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: size, height: size)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ItemRowView(itemIds: [1055, 3047, 3161, 3134, 3364, 1037])
        ItemRowView(itemIds: [1055, 3047])
    }
    .padding()
}
