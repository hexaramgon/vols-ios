//
//  APIModels+Home.swift
//  Services
//
//  DTOs for the Home / Explore revamp (Collab tab, My Network, Music tab).
//  Shapes verified against the live RPCs / tables.
//

import Foundation

/// A feed track with the artist fields the revamp needs — `get_following_feed`,
/// `get_home_feed` and `get_collab_tracks` all return this shape (the last adds
/// `looking_for_collab`). Cover/audio are bare `post-uploads` paths; the
/// avatar is usually a full URL already.
public struct ApiFeedTrack: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String?
    public let artistId: String?
    public let artistProfileImageUrl: String?
    public let coverUrl: String?
    public let audioUrl: String?
    public let streams: Int?
    public let hasVisual: Bool?
    public let durationMs: Int?
    public let genre: String?
    public let lookingForCollab: Bool?
}

/// A `get_open_to_collab_locations` row — the Collab map's opt-in locations.
public struct ApiUserLocation: Codable, Sendable {
    public let userId: String
    public let location: String?
}

// MARK: - Decode-safe required fields

// `title` / `created_by` are non-optional for the call sites, but a null or
// missing value in one row must not fail the whole feed decode — fall back to
// an empty string instead (the UI treats "" like a missing title).

public extension ApiFeedTrack {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        artistId = try c.decodeIfPresent(String.self, forKey: .artistId)
        artistProfileImageUrl = try c.decodeIfPresent(String.self, forKey: .artistProfileImageUrl)
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        audioUrl = try c.decodeIfPresent(String.self, forKey: .audioUrl)
        streams = try c.decodeIfPresent(Int.self, forKey: .streams)
        hasVisual = try c.decodeIfPresent(Bool.self, forKey: .hasVisual)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        lookingForCollab = try c.decodeIfPresent(Bool.self, forKey: .lookingForCollab)
    }
}
