//
//  TabBarItem.swift
//  Volspire
//
//

import SwiftUI

enum TabBarItem: Hashable, CaseIterable {
    case home
    case library
    case search
}

extension TabBarItem {
    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .search: "Search"
        }
    }

    var image: Image {
        switch self {
        case .home: Image(systemName: "house.fill")
        case .library: Image(systemName: "rectangle.stack.badge.play")
        case .search: Image(systemName: "magnifyingglass")
        }
    }

    var role: TabRole? {
        switch self {
        case .search: .search
        default: nil
        }
    }
}
