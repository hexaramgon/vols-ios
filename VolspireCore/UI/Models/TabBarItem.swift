//
//  TabBarItem.swift
//  Volspire
//
//

import SwiftUI

enum TabBarItem: Hashable, CaseIterable {
    case home
    case library
    case newPost
    case search
    case profile
}

extension TabBarItem {
    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .newPost: "New Post"
        case .search: "Search"
        case .profile: "Profile"
        }
    }

    var image: Image {
        switch self {
        case .home: Image(systemName: "house.fill")
        case .library: Image(systemName: "rectangle.stack.badge.play")
        case .newPost: Image(systemName: "plus.circle.fill")
        case .search: Image(systemName: "magnifyingglass")
        case .profile: Image(systemName: "person.fill")
        }
    }

    var role: TabRole? {
        switch self {
        case .search: .search
        default: nil
        }
    }
}
