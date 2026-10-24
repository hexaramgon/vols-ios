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

    /// "m:ss" for the chart rows' trailing length.
    var durationLabel: String? {
        guard let ms = durationMs, ms > 0 else { return nil }
        return (ms / 1000).durationLabel
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

/// Extra card detail for a More-artists card: city + newest public track.
struct ArtistCardDetails: Hashable {
    /// Curated city name when the location resolves, else the raw text.
    let location: String?
    let latestTrack: HomeTrack?
}
