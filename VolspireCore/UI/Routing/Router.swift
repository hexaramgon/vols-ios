//
//  Router.swift
//  Volspire
//
//

import MediaLibrary
import Services
import SwiftUI

enum Route: Hashable, Equatable {
    /// `compactHeader`: Library's Saved tracks — the playlist page's header
    /// with the Saved sleeve instead of the cover-tinted hero.
    /// `savedTracks`: the user's own Saved tracks (Saved sleeve, @you);
    /// otherwise a compact header is one of Volspire's own lists (@volspire).
    case mediaList(_ items: [Media], listMeta: MediaList.Meta?, showSave: Bool = true, compactHeader: Bool = false, savedTracks: Bool = false)
    case profile(_ userId: String)
    case search(_ query: String)
    case notifications
    case messages
    case settings
    case playlists
    case playlist(playlistId: String, title: String)
    /// `highlight`: an item to scroll to and briefly highlight on arrival
    /// (an Activity row about a file in this folder).
    case folderContents(folderId: String, folderName: String, highlight: FolderHighlight? = nil)
    case marketplacePack(ApiMarketplacePack)
    case marketplaceService(ApiMarketplaceService)
    /// The owner's Pack Analytics page (from the card on their pack).
    case packAnalytics(packId: String, packName: String)
    /// The author's Listing Analytics page (from the card on their listing).
    case listingAnalytics(listingId: String, title: String)
    case collabListing(ApiListing)
    case conversation(ActiveConversation)
    case messageCategory(title: String, bucket: MessageBucket)
    case release(releaseId: String, title: String)
    /// The Artist Dashboard, and its Followers & collaborators page — routes
    /// (not NavigationLinks) so a Profile tab re-tap pops them like any page.
    case analytics
    case network
}

@Observable
class Router {
    /// The tab's back-stack. A typed array (not `NavigationPath`) so the
    /// router can see what's already open — see `push(_:)`.
    var path: [Route] = []

    /// Opens `route` — unless that same screen (same listing, chat, profile,
    /// folder…) is already in the back-stack, in which case it goes BACK to
    /// it instead of stacking a copy. Stops loops like chat → listing → chat
    /// → listing… from growing forever (the Instagram / Marketplace pattern).
    private func push(_ route: Route) {
        if let key = route.identity,
           let existing = path.lastIndex(where: { $0.identity == key }) {
            let extra = path.count - 1 - existing
            if extra > 0 { path.removeLast(extra) }
            return
        }
        path.append(route)
    }

    func navigateToMedia(items: [Media], listMeta: MediaList.Meta?, showSave: Bool = true, compactHeader: Bool = false, savedTracks: Bool = false) {
        push(Route.mediaList(items, listMeta: listMeta, showSave: showSave, compactHeader: compactHeader, savedTracks: savedTracks))
    }

    func navigateToProfile(userId: String) {
        push(Route.profile(userId))
    }

    func navigateToSearch(query: String) {
        push(Route.search(query))
    }

    func navigateToNotifications() {
        push(Route.notifications)
    }

    func navigateToMessages() {
        push(Route.messages)
    }

    func navigateToSettings() {
        push(Route.settings)
    }

    func navigateToPlaylists() {
        push(Route.playlists)
    }

    func navigateToPlaylist(playlistId: String, title: String) {
        push(Route.playlist(playlistId: playlistId, title: title))
    }

    func navigateToFolder(folderId: String, folderName: String, highlight: FolderHighlight? = nil) {
        push(Route.folderContents(folderId: folderId, folderName: folderName, highlight: highlight))
    }

    func navigateToMarketplacePack(_ pack: ApiMarketplacePack) {
        push(Route.marketplacePack(pack))
    }

    func navigateToMarketplaceService(_ service: ApiMarketplaceService) {
        push(Route.marketplaceService(service))
    }

    func navigateToRelease(releaseId: String, title: String) {
        push(Route.release(releaseId: releaseId, title: title))
    }

    func navigateToAnalytics() {
        push(Route.analytics)
    }

    func navigateToPackAnalytics(packId: String, packName: String) {
        push(Route.packAnalytics(packId: packId, packName: packName))
    }

    func navigateToListingAnalytics(listingId: String, title: String) {
        push(Route.listingAnalytics(listingId: listingId, title: title))
    }

    func navigateToNetwork() {
        push(Route.network)
    }

    func navigateToCollabListing(_ listing: ApiListing) {
        push(Route.collabListing(listing))
    }

    func navigateToConversation(_ conversation: ActiveConversation) {
        push(Route.conversation(conversation))
    }

    func navigateToMessageCategory(title: String, bucket: MessageBucket) {
        push(Route.messageCategory(title: title, bucket: bucket))
    }

    /// Tab-bar re-tap, iOS-style in two steps: with a screen pushed, it just
    /// pops back to the tab's root — exactly where you left it; already at
    /// the root, it asks the root to scroll to the top (`rootResetTick`).
    /// One tap used to do both, so leaving a pushed profile threw away your
    /// place in the feed.
    func popToRoot() {
        if path.isEmpty {
            rootResetTick += 1
        } else {
            path.removeAll()
        }
    }

    /// Bumped by a `popToRoot` while already at the root (tab-bar re-tap). A
    /// tab's root screen observes it to scroll back to the top (Explore,
    /// Library, Workspace).
    private(set) var rootResetTick = 0
}

private struct RouterViewModifier: ViewModifier {
    /// Externally-owned router, or nil to own one locally.
    let injected: Router?
    @State private var ownedRouter = Router()
    @State private var floatingAction = FloatingActionModel()

    func body(content: Content) -> some View {
        @Bindable var router = injected ?? ownedRouter
        return NavigationStack(path: $router.path) {
            content
                .environment(router)
                .environment(floatingAction)
                .modifier(HiddenWhenTabInactive())
                .navigationDestination(for: Route.self) { route in
                    RoutedView(route: route)
                        .environment(router)
                        .environment(floatingAction)
                        .modifier(HiddenWhenTabInactive())
                }
        }
        .floatingActionOverlay(floatingAction)
    }
}

/// RootTabView keeps visited tabs mounted at opacity 0, which still leaves
/// them in the accessibility tree — VoiceOver would walk the hidden tabs.
/// Applied INSIDE the NavigationStack (root + every pushed screen):
/// `.accessibilityHidden` on the stack itself doesn't reach its UIKit-hosted
/// pages.
private struct HiddenWhenTabInactive: ViewModifier {
    @Environment(\.isActiveRootTab) private var isActiveRootTab

    func body(content: Content) -> some View {
        content.accessibilityHidden(!isActiveRootTab)
    }
}

extension View {
    func withRouter() -> some View {
        modifier(RouterViewModifier(injected: nil))
    }

    /// Uses an externally-owned router (RootTabView keeps one per tab) so
    /// navigation can be driven from outside the tab's own view tree.
    func withRouter(_ router: Router) -> some View {
        modifier(RouterViewModifier(injected: router))
    }
}

extension Route {
    /// "The same screen" for de-duplicating the back-stack: one key per
    /// entity (or per singleton screen). nil = always push (lists built from
    /// arbitrary items, searches).
    var identity: String? {
        switch self {
        case let .profile(userId): "profile:\(userId.lowercased())"
        case let .playlist(playlistId, _): "playlist:\(playlistId.lowercased())"
        case let .folderContents(folderId, _, _): "folder:\(folderId.lowercased())"
        case let .collabListing(listing): "listing:\(listing.listingId.lowercased())"
        case let .conversation(convo): "conversation:\(convo.convoId.lowercased())"
        case let .marketplacePack(pack): "pack:\(pack.packId.lowercased())"
        case let .marketplaceService(service): "service:\(service.serviceId.lowercased())"
        case let .packAnalytics(packId, _): "pack-analytics:\(packId.lowercased())"
        case let .listingAnalytics(listingId, _): "listing-analytics:\(listingId.lowercased())"
        case let .messageCategory(_, bucket): "messages:\(bucket)"
        case .notifications: "notifications"
        case .messages: "messages"
        case .settings: "settings"
        case .playlists: "playlists"
        case let .release(releaseId, _): "release:\(releaseId.lowercased())"
        case .analytics: "analytics"
        case .network: "network"
        case .mediaList, .search: nil
        }
    }

    /// Logical screen name for analytics `page_view` events — the iOS analogue of
    /// the web's pathname.
    var analyticsName: String {
        switch self {
        case .mediaList: "media_list"
        case .profile: "profile"
        case .search: "search"
        case .notifications: "notifications"
        case .messages: "messages"
        case .settings: "settings"
        case .playlists: "playlists"
        case .playlist: "playlist"
        case .folderContents: "folder"
        case .marketplacePack: "marketplace_pack"
        case .marketplaceService: "marketplace_service"
        case .packAnalytics: "pack_analytics"
        case .listingAnalytics: "listing_analytics"
        case .collabListing: "collab_listing"
        case .conversation: "conversation"
        case .messageCategory: "message_category"
        case .release: "release"
        case .analytics: "analytics"
        case .network: "network"
        }
    }

    /// The primary entity id for the screen, when there is one.
    var analyticsId: String? {
        switch self {
        case let .profile(userId): userId
        case let .search(query): query
        case let .playlist(playlistId, _): playlistId
        case let .folderContents(folderId, _, _): folderId
        case let .conversation(convo): convo.convoId
        case let .release(releaseId, _): releaseId
        case let .collabListing(listing): listing.listingId
        // The pack owner's Performance views count these (get_pack_stats).
        case let .marketplacePack(pack): pack.packId
        case let .packAnalytics(packId, _): packId
        case let .listingAnalytics(listingId, _): listingId
        default: nil
        }
    }
}

/// What a folder page should point at when it opens.
enum FolderHighlight: Hashable {
    /// A file in the folder (an upload).
    case file(String)
    /// A track added to the folder.
    case track(String)
    /// A comment on one of its files — the file is looked up from it.
    case fileComment(String)
    /// A file known only by name (the Workspace activity rail's events).
    case fileNamed(String)
}
