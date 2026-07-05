//
//  TabBarItem.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

enum TabBarItem: Hashable, CaseIterable {
    case home       // "Explore"
    case library    // "Library" — saved tracks + Workspace folders
    case newPost
    case inbox       // Messages / conversations
    case profile
}

extension TabBarItem {
    var title: String {
        switch self {
        case .home: "Explore"
        case .library: "Library"
        case .newPost: "New Post"
        case .inbox: "Inbox"
        case .profile: "Profile"
        }
    }

    var image: Image {
        switch self {
        case .home: Image(lucide: .house)
        case .library: Image(lucide: .library)
        case .newPost: Image(lucide: .circlePlus)
        case .inbox: Image(lucide: .inbox)
        case .profile: Image(lucide: .circleUser) // fallback; replaced by avatar in RootTabView
        }
    }
}
