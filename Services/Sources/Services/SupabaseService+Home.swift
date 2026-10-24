//
//  SupabaseService+Home.swift
//  Services
//
//  Home / Explore reads for the web revamp port: role-filtered + paged
//  explore artists, paged following / home feeds with artist fields, the
//  looking-for-collab tracks, and the Collab map's batched table reads.
//

import Foundation
import Supabase

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
    /// location (web `useArtistLocations`).
    func getOpenToCollabLocations(ids: [String]) async throws -> [ApiUserLocation] {
        guard !ids.isEmpty else { return [] }
        let data = try await supabaseClient.from("users")
            .select("user_id, location")
            .in("user_id", values: ids)
            .eq("open_to_collab", value: true)
            .not("location", operator: .is, value: "null")
            .execute()
            .data
        return try JSONDecoder.api.decode([ApiUserLocation].self, from: data)
    }

    /// Location + newest public track for a page of artists (web
    /// `useArtistDetails`): two batched reads, then a per-artist fallback for
    /// anyone a full batch crowded out.
    func getArtistDetails(ids: [String]) async throws -> [String: ApiArtistDetails] {
        guard !ids.isEmpty else { return [:] }
        let columns = "track_id, title, genre, cover_url, audio_url, has_visual, duration_ms, streams, created_by, created_at"
        let batchLimit = ids.count * 4
        async let usersData = supabaseClient.from("users")
            .select("user_id, location")
            .in("user_id", values: ids)
            .execute()
            .data
        async let tracksData = supabaseClient.from("tracks")
            .select(columns)
            .in("created_by", values: ids)
            .eq("visibility", value: "public")
            .eq("deprecated", value: false)
            .order("created_at", ascending: false)
            .limit(batchLimit)
            .execute()
            .data
        let users = try JSONDecoder.api.decode([ApiUserLocation].self, from: try await usersData)
        let tracks = try JSONDecoder.api.decode([ApiArtistLatestTrack].self, from: try await tracksData)

        var latest: [String: ApiArtistLatestTrack] = [:]
        for t in tracks where latest[t.createdBy.lowercased()] == nil { latest[t.createdBy.lowercased()] = t }
        if tracks.count >= batchLimit {
            for id in ids where latest[id.lowercased()] == nil {
                let data = try await supabaseClient.from("tracks")
                    .select(columns)
                    .eq("created_by", value: id)
                    .eq("visibility", value: "public")
                    .eq("deprecated", value: false)
                    .order("created_at", ascending: false)
                    .limit(1)
                    .execute()
                    .data
                if let t = try JSONDecoder.api.decode([ApiArtistLatestTrack].self, from: data).first {
                    latest[id.lowercased()] = t
                }
            }
        }
        let locations = Dictionary(users.map { ($0.userId.lowercased(), $0.location) }, uniquingKeysWith: { a, _ in a })
        var out: [String: ApiArtistDetails] = [:]
        for id in ids {
            let k = id.lowercased()
            out[k] = ApiArtistDetails(location: locations[k] ?? nil, latestTrack: latest[k])
        }
        return out
    }
}
