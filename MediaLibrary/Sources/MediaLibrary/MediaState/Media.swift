//
//  Media.swift
//  MediaLibrary
//

import Foundation

/// A single playable media item (track/song).
public struct Media: Identifiable, Hashable, Equatable, Sendable {
    public let id: MediaID
    public let meta: MediaMeta

    public init(id: MediaID, meta: MediaMeta) {
        self.id = id
        self.meta = meta
    }
}

/// A unique identifier for a media item.
public struct MediaID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var asString: String { value }
    public var description: String { value }
}
