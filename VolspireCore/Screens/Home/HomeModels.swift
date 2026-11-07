//
//  HomeModels.swift
//  Volspire
//
//  UI models for the Home / Explore tabs, mapped at ingest (URLs resolved
//  once) by FeedStore and the Home view model.
//

import Foundation

/// A home feed / chart track row.
struct HomeTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let coverURL: URL?
    let audioURL: URL?
    let streams: Int?
    let durationMs: Int?
    var artistId: String? = nil
    var artistAvatarURL: URL? = nil
    var genre: String? = nil
    var hasVisual: Bool = false
    var lookingForCollab: Bool = false
    /// ISO upload time (Spotlight's "N plays · 3d").
    var createdAt: String? = nil

    /// "Track" / "Short Track" / "Snippet" — the web's duration buckets
    /// (> 2:00 track, < 0:30 snippet, else short track).
    var typeLabel: String {
        guard let ms = durationMs else { return "Track" }
        if ms > 120_000 { return "Track" }
        if ms < 30_000 { return "Snippet" }
        return "Short Track"
    }
}

struct ExploreArtistItem: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: URL?
    let monthlyListeners: Int
    var followersCount: Int = 0
    var tags: [String] = []
    var isFollowing: Bool
}

/// An open-to-collab artist pinned to a curated city (Collab map + Nearby).
struct LocatedArtist: Identifiable, Hashable {
    let artist: ExploreArtistItem
    let place: GeoPlace
    var id: String { artist.id }
}
