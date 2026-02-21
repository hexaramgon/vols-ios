//
//  SupabaseService.swift
//  Services
//
//  Created by GitHub Copilot on 01.02.2026.
//

import Foundation
import Supabase

// MARK: - Supabase Configuration

public enum SupabaseConfig {
    public static let baseURL = "https://xkznkdxhynzrmwupufay.supabase.co"
    public static let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhrem5rZHhoeW56cm13dXB1ZmF5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY2NzE3MDYsImV4cCI6MjA2MjI0NzcwNn0.yiRjLdzjAAAFJFfLT60ebqXeIF3mvj-UO8qtFq-Tyac"
    public static let redirectURL = "volspire://auth/callback"
}

// MARK: - Shared Supabase Client

public let supabaseClient = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.baseURL)!,
    supabaseKey: SupabaseConfig.apiKey
)

// MARK: - Home API Response Models

public struct HomeTracksResponse: Codable, Sendable {
    public let featuredItems: [ApiFeaturedItem]?
    public let recommendedTracks: [ApiHomeTrack]?
    public let trendingTracks: [ApiHomeTrack]?
    public let newReleases: [ApiHomeTrack]?
    public let recentlyPlayed: [ApiHomeTrack]?
    public let topProducers: [ApiProducer]?
    public let following: [ApiUser]?
    
    enum CodingKeys: String, CodingKey {
        case featuredItems = "featured_items"
        case recommendedTracks = "recommended_tracks"
        case trendingTracks = "trending_tracks"
        case newReleases = "new_releases"
        case recentlyPlayed = "recently_played"
        case topProducers = "top_producers"
        case following
    }
}

public struct ApiFeaturedItem: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let label: String?
    public let imageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case label
        case imageUrl = "image_url"
    }
}

public struct ApiHomeTrack: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String?
    public let coverUrl: String?
    public let audioUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
    }
}

public struct ApiProducer: Codable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let profileImageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case profileImageUrl = "profile_image_url"
    }
}

public struct ApiUser: Codable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let profileImageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case profileImageUrl = "profile_image_url"
    }
}

// MARK: - User Profile Response Models

public struct ApiUserProfile: Codable, Sendable {
    public let userId: String
    public let username: String?
    public let bio: String?
    public let profileImageUrl: String?
    public let bannerImageUrl: String?
    public let location: String?
    public let followersCount: Int?
    public let monthlyListenersCount: Int
    public let trackCount: Int
    public let tracks: [ApiProfileTrack]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, bio
        case profileImageUrl = "profile_image_url"
        case bannerImageUrl = "banner_image_url"
        case location
        case followersCount = "followers_count"
        case monthlyListenersCount = "monthly_listeners_count"
        case trackCount = "track_count"
        case tracks
    }
}

public struct ApiProfileTrack: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let coverUrl: String?
    public let audioUrl: String?
    public let streams: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, title, streams
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
    }
}

// MARK: - Supabase Service Protocol

public protocol SupabaseServiceProtocol: Sendable {
    func getHomeTracks() async throws -> HomeTracksResponse
    func getUserProfile(userId: String) async throws -> ApiUserProfile
    func rpc<T: Decodable>(_ functionName: String, params: [String: Any]?) async throws -> T
}

// MARK: - Supabase Service Implementation

public final class SupabaseService: SupabaseServiceProtocol, Sendable {
    private let client: SupabaseClient
    private let cache: APICache

    public init(client: SupabaseClient = supabaseClient, cache: APICache = .shared) {
        self.client = client
        self.cache = cache
    }

    // MARK: - Public Methods

    /// Fetches home tracks data from Supabase RPC function (cached 5 min)
    public func getHomeTracks() async throws -> HomeTracksResponse {
        return try await cachedRpc("get_home_tracks", params: nil, ttl: 300)
    }

    /// Fetches a user profile from Supabase RPC function (cached 5 min)
    public func getUserProfile(userId: String) async throws -> ApiUserProfile {
        return try await cachedRpc("get_user_profile", params: ["profile_id": userId], ttl: 300)
    }

    /// Generic RPC call to Supabase (no cache)
    public func rpc<T: Decodable>(_ functionName: String, params: [String: Any]? = nil) async throws -> T {
        return try await performRpc(functionName, params: params)
    }

    /// Generic RPC call with caching
    public func cachedRpc<T: Decodable & Encodable & Sendable>(
        _ functionName: String,
        params: [String: Any]? = nil,
        ttl: TimeInterval = APICache.defaultTTL
    ) async throws -> T {
        let cacheKey = APICache.key(functionName, params: params)

        // Return cached data if available
        if let cached: T = await cache.get(cacheKey) {
            print("[SupabaseService] rpc(\(functionName)) CACHE HIT")
            return cached
        }

        // Fetch from network
        let result: T = try await performRpc(functionName, params: params)

        // Store in cache
        await cache.set(cacheKey, value: result, ttl: ttl)

        return result
    }

    // MARK: - Private

    private func performRpc<T: Decodable>(_ functionName: String, params: [String: Any]? = nil) async throws -> T {
        do {
            if let params = params {
                let jsonData = try JSONSerialization.data(withJSONObject: params)
                let anyJSON = try JSONDecoder().decode(AnyJSON.self, from: jsonData)

                let response = try await client.rpc(functionName, params: anyJSON)
                    .execute()
                print("[SupabaseService] rpc(\(functionName)) status: \(response.status), bytes: \(response.data.count)")
                return try JSONDecoder().decode(T.self, from: response.data)
            } else {
                let response = try await client.rpc(functionName)
                    .execute()
                print("[SupabaseService] rpc(\(functionName)) status: \(response.status), bytes: \(response.data.count)")
                return try JSONDecoder().decode(T.self, from: response.data)
            }
        } catch {
            print("[SupabaseService] rpc(\(functionName)) ERROR: \(error)")
            throw mapError(error)
        }
    }

    private func mapError(_ error: Error) -> SupabaseError {
        if let urlError = error as? URLError {
            return .serverError("Network error: \(urlError.localizedDescription)")
        }
        if error is DecodingError {
            return .decodingError(error)
        }
        return .serverError(error.localizedDescription)
    }
}

// MARK: - Supabase Error Types

public enum SupabaseError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case clientError(Int)
    case serverError(String)
    case decodingError(Error)
    case unknown(Int)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from Supabase"
        case .unauthorized:
            return "Unauthorized - check API key"
        case .notFound:
            return "Resource not found"
        case .clientError(let code):
            return "Client error: \(code)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unknown(let code):
            return "Unknown error: \(code)"
        }
    }
}
