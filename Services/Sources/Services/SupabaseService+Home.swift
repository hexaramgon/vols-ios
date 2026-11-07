//
//  SupabaseService+Home.swift
//  Services
//
//  Home / Explore reads for the web revamp port: role-filtered + paged
//  explore artists, paged following / home feeds with artist fields, the
//  looking-for-collab tracks, and the Collab map's opt-in locations.
//

import Foundation

public extension SupabaseService {
    /// Explore artists, filtered by role tags (nil/empty = everyone) and paged
    /// (web page size 24). Cached per params.
    func getExploreArtists(roles: [String], limit: Int, offset: Int) async throws -> [ApiExploreArtist] {
        let params: [String: Any] = [
            "p_roles": roles.isEmpty ? NSNull() : roles.sorted(),
            "p_limit": limit,
            "p_offset": offset,
        ]
        return try await cachedRpc("get_explore_artists", params: params, ttl: CacheTTL.medium)
    }

    /// My Network: releases from followed accounts, paged (web 24/page).
    func getFollowingFeedPage(limit: Int, offset: Int) async throws -> [ApiFeedTrack] {
        try await cachedRpc("get_following_feed", params: ["p_limit": limit, "p_offset": offset], ttl: CacheTTL.short)
    }

    /// Tracks their owners flagged "looking for collab" (`get_collab_tracks`).
    func getCollabTracks(limit: Int = 24, offset: Int = 0) async throws -> [ApiFeedTrack] {
        try await cachedRpc("get_collab_tracks", params: ["p_limit": limit, "p_offset": offset], ttl: CacheTTL.medium)
    }

    /// Opt-in map locations for `ids`: only `open_to_collab` users with a
    /// location (`get_open_to_collab_locations`; web `useArtistLocations`).
    func getOpenToCollabLocations(ids: [String]) async throws -> [ApiUserLocation] {
        guard !ids.isEmpty else { return [] }
        return try await cachedRpc("get_open_to_collab_locations", params: ["p_user_ids": ids], ttl: CacheTTL.medium)
    }
}
