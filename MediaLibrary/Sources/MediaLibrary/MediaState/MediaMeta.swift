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
        self.genre = genre
        self.audioURL = audioURL
        self.duration = duration
        self.timestamp = timestamp
    }
}
