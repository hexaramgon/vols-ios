//
//  Router.swift
//  Volspire
//
//

import MediaLibrary
import SwiftUI

enum Route: Hashable, Equatable {
    case mediaList(_ items: [Media], listMeta: MediaList.Meta?)
    case mediaItem(_ item: Media)
    case downloaded
}

@Observable
class Router {
    var path = NavigationPath()

    func navigateToMedia(items: [Media], listMeta: MediaList.Meta?) {
        path.append(Route.mediaList(items, listMeta: listMeta))
    }

    func navigateToMedia(item: Media) {
        path.append(Route.mediaItem(item))
    }

    func navigateToDownloaded() {
        path.append(Route.downloaded)
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

private struct RouterViewModifier: ViewModifier {
    @State private var router = Router()
    func body(content: Content) -> some View {
        NavigationStack(path: $router.path) {
            content
                .environment(router)
                .navigationDestination(for: Route.self) { route in
                    RoutedView(route: route)
                        .environment(router)
                }
        }
    }
}

extension View {
    func withRouter() -> some View {
        modifier(RouterViewModifier())
    }
}
