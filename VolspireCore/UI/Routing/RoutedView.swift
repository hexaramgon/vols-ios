//
//  RoutedView.swift
//  Volspire
//
//

import SwiftUI

struct RoutedView: View {
    let route: Route

    var body: some View {
        switch route {
        case let .mediaList(items, listMeta):
            MediaListScreen(items: items, listMeta: listMeta)
        case let .mediaItem(item):
            MediaItemScreen(item: item)
        case .downloaded:
            DownloadedScreen()
        case let .profile(userId):
            ProfileScreen(userId: userId)
        }
    }
}
