//
//  Router.swift
//  Volspire
//
//

import MediaLibrary
import Services
import SwiftUI

enum Route: Hashable, Equatable {
    case mediaList(_ items: [Media], listMeta: MediaList.Meta?, showSave: Bool = true)
    case mediaItem(_ item: Media)
    case downloaded
    case profile(_ userId: String)
    case search(_ query: String)
    case notifications
    case messages
    case settings
    case workspace
    case playlists
    case playlist(playlistId: String, title: String)
    case folderContents(folderId: String, folderName: String)
    case marketplacePack(ApiMarketplacePack)
    case marketplaceService(ApiMarketplaceService)
    case collabListing(ApiListing)
    case conversation(ActiveConversation)
    case messageCategory(title: String, items: [ConversationItem])
}

@Observable
class Router {
    var path = NavigationPath()

    func navigateToMedia(items: [Media], listMeta: MediaList.Meta?, showSave: Bool = true) {
        path.append(Route.mediaList(items, listMeta: listMeta, showSave: showSave))
    }

    func navigateToMedia(item: Media) {
        path.append(Route.mediaItem(item))
    }

    func navigateToDownloaded() {
        path.append(Route.downloaded)
    }

    func navigateToProfile(userId: String) {
        path.append(Route.profile(userId))
    }

    func navigateToSearch(query: String) {
        path.append(Route.search(query))
    }

    func navigateToNotifications() {
        path.append(Route.notifications)
    }

    func navigateToMessages() {
        path.append(Route.messages)
    }

    func navigateToSettings() {
        path.append(Route.settings)
    }

    func navigateToWorkspace() {
        path.append(Route.workspace)
    }

    func navigateToPlaylists() {
        path.append(Route.playlists)
    }

    func navigateToPlaylist(playlistId: String, title: String) {
        path.append(Route.playlist(playlistId: playlistId, title: title))
    }

    func navigateToFolder(folderId: String, folderName: String) {
        path.append(Route.folderContents(folderId: folderId, folderName: folderName))
    }

    func navigateToMarketplacePack(_ pack: ApiMarketplacePack) {
        path.append(Route.marketplacePack(pack))
    }

    func navigateToMarketplaceService(_ service: ApiMarketplaceService) {
        path.append(Route.marketplaceService(service))
    }

    func navigateToCollabListing(_ listing: ApiListing) {
        path.append(Route.collabListing(listing))
    }

    func navigateToConversation(_ conversation: ActiveConversation) {
        path.append(Route.conversation(conversation))
    }

    func navigateToMessageCategory(title: String, items: [ConversationItem]) {
        path.append(Route.messageCategory(title: title, items: items))
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

private struct RouterViewModifier: ViewModifier {
    @State private var router = Router()
    @State private var floatingAction = FloatingActionModel()
    func body(content: Content) -> some View {
        NavigationStack(path: $router.path) {
            content
                .environment(router)
                .environment(floatingAction)
                .navigationDestination(for: Route.self) { route in
                    RoutedView(route: route)
                        .environment(router)
                        .environment(floatingAction)
                }
        }
        .floatingActionOverlay(floatingAction)
    }
}

private struct InjectedRouterViewModifier: ViewModifier {
    let router: Router
    @State private var floatingAction = FloatingActionModel()
    func body(content: Content) -> some View {
        @Bindable var router = router
        return NavigationStack(path: $router.path) {
            content
                .environment(router)
                .environment(floatingAction)
                .navigationDestination(for: Route.self) { route in
                    RoutedView(route: route)
                        .environment(router)
                        .environment(floatingAction)
                }
        }
        .floatingActionOverlay(floatingAction)
    }
}

extension View {
    func withRouter() -> some View {
        modifier(RouterViewModifier())
    }

    /// Uses an externally-owned router (RootTabView keeps one per tab) so
    /// navigation can be driven from outside the tab's own view tree.
    func withRouter(_ router: Router) -> some View {
        modifier(InjectedRouterViewModifier(router: router))
    }
}

extension Route {
    /// Logical screen name for analytics `page_view` events — the iOS analogue of
    /// the web's pathname.
    var analyticsName: String {
        switch self {
        case .mediaList: "media_list"
        case .mediaItem: "track"
        case .downloaded: "downloaded"
        case .profile: "profile"
        case .search: "search"
        case .notifications: "notifications"
        case .messages: "messages"
        case .settings: "settings"
        case .workspace: "workspace"
        case .playlists: "playlists"
        case .playlist: "playlist"
        case .folderContents: "folder"
        case .marketplacePack: "marketplace_pack"
        case .marketplaceService: "marketplace_service"
        case .collabListing: "collab_listing"
        case .conversation: "conversation"
        case .messageCategory: "message_category"
        }
    }

    /// The primary entity id for the screen, when there is one.
    var analyticsId: String? {
        switch self {
        case let .mediaItem(item): item.id.value
        case let .profile(userId): userId
        case let .search(query): query
        case let .playlist(playlistId, _): playlistId
        case let .folderContents(folderId, _): folderId
        case let .conversation(convo): convo.convoId
        default: nil
        }
    }
}
