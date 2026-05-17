//
//  LOLIVEWidgetsBundle.swift
//  LOLIVEWidgets
//

import WidgetKit
import SwiftUI

@main
struct LOLIVEWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FavoriteTeamWidget()
        MatchLiveActivityWidget()
    }
}
