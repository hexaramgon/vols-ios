//
//  MediaList.swift
//  MediaLibrary
//

import Foundation

/// A collection of media items (e.g. an album, playlist).
public struct MediaList: Identifiable, Hashable, Equatable, Sendable {
    public let id: MediaListID
    public let meta: Meta
    public let items: [Media]

    public struct Meta: Hashable, Equatable, Sendable {
        public let artwork: URL?
        public let title: String
        public let subtitle: String?
        public let timestamp: Date?

        public init(artwork: URL?, title: String, subtitle: String? = nil, timestamp: Date? = nil) {
            self.artwork = artwork
            self.title = title
            self.subtitle = subtitle
            self.timestamp = timestamp
        }
    }

    public init(id: MediaListID, meta: Meta, items: [Media]) {
        self.id = id
        self.meta = meta
        self.items = items
    }
}

public extension MediaList {
    static let empty: MediaList = .init(
        id: .init("empty"),
        meta: .init(artwork: nil, title: ""),
        items: []
    )
}

/// A unique identifier for a media list (playlist/album).
public struct MediaListID: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var asString: String { value }
    public var description: String { value }
}
