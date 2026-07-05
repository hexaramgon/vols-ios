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
        case let .mediaItem(item):
            MediaItemScreen(item: item)
        case .downloaded:
            DownloadedScreen()
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
        case .workspace:
            WorkspaceScreen()
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
