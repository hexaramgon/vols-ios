//
//  TabBarItem.swift
//  Volspire
//
//

import SwiftUI

enum TabBarItem: Hashable, CaseIterable {
    case home
    case workspace
    case newPost
    case library
    case profile
}

extension TabBarItem {
    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .newPost: "New Post"
        case .workspace: "Workspace"
        case .profile: "Profile"
        }
    }

    var image: Image {
        switch self {
        case .home: Image(systemName: "house.fill")
        case .library: Image(systemName: "rectangle.stack.badge.play")
        case .newPost: Image(systemName: "plus.circle.fill")
        case .workspace: Image(systemName: "folder.fill")
        case .profile: Image(systemName: "person.fill")
        }
    }

    var role: TabRole? {
        nil
    }
}
