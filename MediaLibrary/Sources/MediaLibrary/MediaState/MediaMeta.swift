//
//  MediaMeta.swift
//  MediaLibrary
//

import Foundation

/// Metadata describing a media item (track/song).
public struct MediaMeta: Equatable, Hashable, Sendable {
    public let artwork: URL?
    public let title: String
    public let subtitle: String?
    public let description: String?
    public let artist: String?
    /// The artist's user id, when the source row carries one — lets a block
    /// drop every queued track of theirs (nil: fall back to the username).
    public let artistId: String?
    public let genre: String?
    public let audioURL: URL?
    public let duration: TimeInterval?
    public let timestamp: Date?

    public init(
        artwork: URL?,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        artist: String? = nil,
        artistId: String? = nil,
        genre: String? = nil,
        audioURL: URL? = nil,
        duration: TimeInterval? = nil,
        timestamp: Date? = nil
    ) {
        self.artwork = artwork
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.artist = artist
        self.artistId = artistId
        self.genre = genre
        self.audioURL = audioURL
        self.duration = duration
        self.timestamp = timestamp
    }
}
