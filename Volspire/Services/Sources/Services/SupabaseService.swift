//
//  SupabaseService.swift
//  Services
//
//  Created by GitHub Copilot on 01.02.2026.
//

import Foundation

// MARK: - Supabase Configuration

public enum SupabaseConfig {
    public static let baseURL = "https://xkznkdxhynzrmwupufay.supabase.co"
    public static let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhrem5rZHhoeW56cm13dXB1ZmF5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY2NzE3MDYsImV4cCI6MjA2MjI0NzcwNn0.yiRjLdzjAAAFJFfLT60ebqXeIF3mvj-UO8qtFq-Tyac"
}

// MARK: - Supabase Headers

public enum SupabaseHeader {
    static let apiKey = "apikey"
    static let authorization = "Authorization"
    static let contentType = "Content-Type"
    static let prefer = "Prefer"
}

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

// MARK: - Supabase Service Protocol

public protocol SupabaseServiceProtocol: Sendable {
    func getHomeTracks() async throws -> HomeTracksResponse
    func rpc<T: Decodable>(_ functionName: String, params: [String: Any]?) async throws -> T
}

// MARK: - Supabase Service Implementation

public final class SupabaseService: SupabaseServiceProtocol, Sendable {
    private let baseURL: String
    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    public init(
        baseURL: String = SupabaseConfig.baseURL,
        apiKey: String = SupabaseConfig.apiKey,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
        
        // Configure decoder - using explicit CodingKeys for snake_case mapping
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Public Methods
    
    /// Fetches home tracks data from Supabase RPC function
    public func getHomeTracks() async throws -> HomeTracksResponse {
        return try await rpc("get_home_tracks", params: nil)
    }
    
    /// Generic RPC call to Supabase
    public func rpc<T: Decodable>(_ functionName: String, params: [String: Any]? = nil) async throws -> T {
        let path = "/rest/v1/rpc/\(functionName)"
        let request = try buildRequest(path: path, method: .post, body: params)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        try validateStatusCode(httpResponse.statusCode)
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // If decoding fails, try to get error message from response
            if let errorResponse = try? JSONDecoder().decode(SupabaseErrorResponse.self, from: data) {
                throw SupabaseError.serverError(errorResponse.message ?? "Unknown error")
            }
            throw SupabaseError.decodingError(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func buildRequest(
        path: String,
        method: HTTPMethod,
        body: [String: Any]? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30
        
        // Set Supabase-specific headers
        request.setValue("application/json", forHTTPHeaderField: SupabaseHeader.contentType)
        request.setValue(apiKey, forHTTPHeaderField: SupabaseHeader.apiKey)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: SupabaseHeader.authorization)
        
        // Set body if provided
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return request
    }
    
    private func validateStatusCode(_ statusCode: Int) throws {
        switch statusCode {
        case 200...299:
            return // Success
        case 401:
            throw SupabaseError.unauthorized
        case 404:
            throw SupabaseError.notFound
        case 400...499:
            throw SupabaseError.clientError(statusCode)
        case 500...599:
            throw SupabaseError.serverError("Server error: \(statusCode)")
        default:
            throw SupabaseError.unknown(statusCode)
        }
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

// MARK: - Supabase Error Response

struct SupabaseErrorResponse: Codable {
    let message: String?
    let code: String?
    let hint: String?
    let details: String?
}
