//
//  MediaItem.swift
//  MediaLibrary
//

import DesignSystem
import Foundation

/// Represents either a single media item or a media list for display.
public enum MediaItem: Identifiable {
    public var id: String {
        switch self {
        case let .mediaList(item): item.id.asString
        case let .mediaItem(item): item.id.asString
        }
    }

    case mediaList(MediaList)
    case mediaItem(Media)
}

public extension MediaItem {
    struct Label {
        public let title: String
        public let subtitle: String?
        public let artwork: Artwork

        public init(title: String, subtitle: String?, artwork: Artwork) {
            self.title = title
            self.subtitle = subtitle
            self.artwork = artwork
        }
    }

    var label: Label {
        switch self {
        case let .mediaList(mediaList):
            .init(
                title: mediaList.meta.title,
                subtitle: mediaList.meta.subtitle,
                artwork: .album(mediaList.meta.artwork)
            )
        case let .mediaItem(media):
            .init(
                title: media.meta.title,
                subtitle: media.meta.subtitle,
                artwork: media.meta.artwork.map { .webImage($0) } ?? .radio(name: media.meta.title)
            )
        }
    }

    var timestamp: Date {
        switch self {
        case let .mediaList(mediaList):
            mediaList.meta.timestamp ?? Date()
        case let .mediaItem(media):
            media.meta.timestamp ?? Date()
        }
    }
}
