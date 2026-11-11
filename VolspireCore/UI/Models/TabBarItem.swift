//
//  TabBarItem.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

enum TabBarItem: Hashable, CaseIterable {
    case home       // "Explore"; Messages + Notifications open from its header
    case library    // "Library" — playlists, saved tracks, music lists
    case newPost
    case workspace  // Workspace folders
    case profile
}

extension TabBarItem {
    var title: String {
        switch self {
        case .home: "Explore"
        case .library: "Library"
        case .newPost: "New Post"
        case .workspace: "Workspace"
        case .profile: "Profile"
        }
    }

    var image: Image {
        switch self {
        case .home: Image(lucide: .house)
        case .library: Image(lucide: .library)
        case .newPost: Image(lucide: .circlePlus)
        case .workspace: Image(lucide: .folder)
        case .profile: Image(lucide: .user)
        }
    }
}
