//
//  RoutedView.swift
//  Volspire
//
//

import Services
import SwiftUI

struct RoutedView: View {
    let route: Route
    @Environment(SocialStore.self) private var socialStore

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

    /// Owner line for app-made lists: your own Saved tracks show @you (taps
    /// to your profile); Volspire's suggestion lists show @volspire.
    private func listHeader(savedTracks: Bool) -> PlaylistHeaderInfo {
        guard savedTracks else { return PlaylistHeaderInfo(ownerUsername: "volspire", volspireMark: true) }
        let me = socialStore.myProfile
        return PlaylistHeaderInfo(ownerUsername: me?.username, ownerId: me?.userId, isSaved: true)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case let .mediaList(items, listMeta, showSave, compactHeader, savedTracks):
            MediaCollectionScreen(items: items, listMeta: listMeta, showSave: showSave,
                                  playlistHeader: compactHeader ? listHeader(savedTracks: savedTracks) : nil)
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
        case let .folderContents(folderId, folderName, highlight):
            FolderContentsScreen(folderId: folderId, folderName: folderName, highlight: highlight)
        case let .marketplacePack(pack):
            MarketplaceDetailScreen(pack: pack)
        case let .marketplaceService(service):
            MarketplaceDetailScreen(service: service)
        case let .packAnalytics(packId, packName, coverURL):
            PackAnalyticsScreen(packId: packId, packName: packName, coverURL: coverURL)
        case let .listingAnalytics(listingId, title, category):
            ListingAnalyticsScreen(listingId: listingId, listingTitle: title, category: category)
        case let .collabListing(listing):
            ListingDetailScreen(listing: listing)
        case let .conversation(convo):
            ConversationScreen(conversation: convo)
        case let .messageCategory(title, bucket):
            MessageCategoryScreen(title: title, bucket: bucket)
        case .analytics:
            AnalyticsScreen()
        case .network:
            NetworkScreen()
        case let .release(releaseId, title):
            ReleaseDetailScreen(releaseId: releaseId, title: title)
        }
    }
}
