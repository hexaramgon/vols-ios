//
//  MediaListSwipeButton.swift
//  Volspire
//
//

import SwiftUI

enum MediaListSwipeButton: Hashable {
    case download
    case delete
}

extension MediaListSwipeButton {
    var systemImage: String {
        switch self {
        case .download:
            "arrow.down"
        case .delete:
            "trash"
        }
    }

    var label: String {
        switch self {
        case .download: "Download"
        case .delete: "Delete"
        }
    }

    var color: Color {
        switch self {
        case .download: Color(.systemBlue)
        case .delete: Color(.systemRed)
        }
    }
}
