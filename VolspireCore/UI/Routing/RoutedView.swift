//
//  RoutedView.swift
//  Volspire
//
//

import Services
import SwiftUI

struct RoutedView: View {
    let route: Route

    var body: some View {
        content
            // Every pushed page sits on the app's one base colour (`appBase`),
            // so screens that don't paint their own background can never fall
            // back to the system black and drift from the tab roots.
            .background(Color.vBase.ignoresSafeArea())
            .onAppear {
                AnalyticsService.shared?.log(.pageView, metadata: pageViewMetadata)
            }
    }

    private var pageViewMetadata: [String: AnalyticsValue] {
        var meta: [String: AnalyticsValue] = ["to": .string(route.analyticsName)]
        if let id = route.analyticsId { meta["id"] = .string(id) }
        return meta
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case let .mediaList(items, listMeta, showSave):
            MediaCollectionScreen(items: items, listMeta: listMeta, showSave: showSave)
        case let .profile(userId):
            ProfileScreen(userId: userId)
        case let .search(query):
            SearchScreen(initialQuery: query)
        case .notifications:
            NotificationsScreen()
        case .messages:
            MessagesScreen()
        case .settings:
            SettingsScreen()
        case .playlists:
            PlaylistsScreen()
        case let .playlist(playlistId, title):
            PlaylistDetailScreen(playlistId: playlistId, title: title)
        case let .folderContents(folderId, folderName):
            FolderContentsScreen(folderId: folderId, folderName: folderName)
        case let .marketplacePack(pack):
            MarketplaceDetailScreen(pack: pack)
        case let .marketplaceService(service):
            MarketplaceDetailScreen(service: service)
        case let .collabListing(listing):
            ListingDetailScreen(listing: listing)
        case let .conversation(convo):
            ConversationScreen(conversation: convo)
        case let .messageCategory(title, items):
            MessageCategoryScreen(title: title, items: items)
        }
    }
}
