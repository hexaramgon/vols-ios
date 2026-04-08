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
    public let accountType: String?
    public let profileImageUrl: String?
    public let bannerImageUrl: String?
    public let location: String?
    public let tags: String?
    public let followersCount: Int?
    public let monthlyListenersCount: Int
    public let trackCount: Int
    public let tracks: [ApiProfileTrack]
    public let services: [ApiUserService]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, bio, tags
        case accountType = "account_type"
        case profileImageUrl = "profile_image_url"
        case bannerImageUrl = "banner_image_url"
        case location
        case followersCount = "followers_count"
        case monthlyListenersCount = "monthly_listeners_count"
        case trackCount = "track_count"
        case tracks, services
    }
}

public struct ApiUpdateProfileResponse: Codable, Sendable {
    public let userId: String
    public let username: String?
    public let bio: String?
    public let accountType: String?
    public let location: String?
    public let profileImageUrl: String?
    public let bannerImageUrl: String?
    public let tags: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, bio, tags
        case accountType = "account_type"
        case location
        case profileImageUrl = "profile_image_url"
        case bannerImageUrl = "banner_image_url"
    }
}

public struct ApiUserService: Codable, Sendable, Identifiable {
    public var id: String { serviceId }
    public let serviceId: String
    public let title: String
    public let description: String?
    public let serviceType: String?
    public let price: Double?
    public let currency: String?
    public let deliveryTimeDays: Int?
    
    enum CodingKeys: String, CodingKey {
        case serviceId = "service_id"
        case title, description, price, currency
        case serviceType = "service_type"
        case deliveryTimeDays = "delivery_time_days"
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

// MARK: - Folder File DTOs

public struct ApiFolderFile: Codable, Sendable, Identifiable {
    public var id: String { fileId }
    public let fileId: String
    public let name: String
    public let fileUrl: String?
    public let fileType: String?
    public let fileSize: Int?
    public let timespan: Double?
    public let ownerId: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case name
        case fileUrl = "file_url"
        case fileType = "file_type"
        case fileSize = "file_size"
        case timespan
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

// MARK: - User Folder DTOs

public struct ApiUserFolder: Codable, Sendable, Identifiable {
    public var id: String { folderId }
    public let folderId: String
    public let name: String
    public let description: String?
    public let ownerId: String
    public let createdAt: String
    public let role: String

    enum CodingKeys: String, CodingKey {
        case folderId = "folder_id"
        case name
        case description
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case role
    }
}

// MARK: - Notification DTOs

public struct ApiNotificationActor: Codable, Sendable {
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

public struct ApiNotification: Codable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let action: String
    public let objectType: String?
    public let objectId: String?
    public let contextType: String?
    public let contextId: String?
    public let isRead: Bool
    public let actor: ApiNotificationActor?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case action
        case objectType = "object_type"
        case objectId = "object_id"
        case contextType = "context_type"
        case contextId = "context_id"
        case isRead = "is_read"
        case actor
    }
}

// MARK: - Supabase Service Protocol

public protocol SupabaseServiceProtocol: Sendable {
    func getHomeTracks() async throws -> HomeTracksResponse
    func getUserProfile(userId: String) async throws -> ApiUserProfile
    func getUserLikes() async throws -> [ApiUserLike]
    func getUserNotifications() async throws -> [ApiNotification]
    func getUserFolders() async throws -> [ApiUserFolder]
    func getFolderFiles(folderId: String) async throws -> [ApiFolderFile]
    func toggleFollow(targetUser: String) async throws
    func createFolder(name: String, description: String?) async throws
    func editFolder(folderId: String, name: String, description: String?) async throws
    func uploadFile(folderId: String, fileName: String, fileData: Data, fileType: String, fileSize: Int) async throws
    func deleteFile(fileId: String, folderId: String) async throws
    func createUserService(title: String, description: String, serviceType: String, price: Double, currency: String, deliveryTimeDays: Int?) async throws -> ApiUserService
    func updateUserService(serviceId: String, title: String?, description: String?, serviceType: String?, price: Double?, currency: String?, deliveryTimeDays: Int?, isActive: Bool?) async throws -> ApiUserService
    func updateUserProfile(userId: String, username: String?, bio: String?, accountType: String?, location: String?, profileImageUrl: String?, bannerImageUrl: String?, tags: String?) async throws -> ApiUpdateProfileResponse
    func uploadAvatar(userId: String, imageData: Data) async throws -> URL
    func uploadBanner(userId: String, imageData: Data) async throws -> URL
    func removeTrackLike(trackId: String) async throws
    func rpc<T: Decodable>(_ functionName: String, params: [String: Any]?) async throws -> T
    func uploadPost(userId: String, title: String, description: String?, audioData: Data?, audioFileName: String?, videoData: Data?, videoFileName: String?, coverData: Data?, coverFileName: String?, postType: String) async throws
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

    /// Fetches the current user's liked tracks (cached 1 min)
    public func getUserLikes() async throws -> [ApiUserLike] {
        return try await cachedRpc("get_user_likes", params: nil, ttl: 60)
    }

    /// Fetches the current user's notifications (cached 30s)
    public func getUserNotifications() async throws -> [ApiNotification] {
        return try await cachedRpc("get_user_notifications", params: nil, ttl: 30)
    }

    /// Fetches the current user's folders (cached 1 min)
    public func getUserFolders() async throws -> [ApiUserFolder] {
        return try await cachedRpc("get_user_folders", params: nil, ttl: 60)
    }

    /// Fetches files in a folder from Supabase RPC function (cached 1 min)
    public func getFolderFiles(folderId: String) async throws -> [ApiFolderFile] {
        return try await cachedRpc("get_folder_files", params: ["p_folder_id": folderId], ttl: 60)
    }

    /// Toggles follow/unfollow for a user
    public func toggleFollow(targetUser: String) async throws {
        let _: AnyJSON = try await performRpc("toggle_user_follow", params: ["target_user": targetUser])
        // Invalidate cached profile for this user
        let cacheKey = APICache.key("get_user_profile", params: ["profile_id": targetUser])
        await cache.remove(cacheKey)
    }

    /// Creates a new folder via Supabase RPC function
    public func createFolder(name: String, description: String?) async throws {
        var params: [String: Any] = ["p_name": name]
        if let description, !description.isEmpty {
            params["p_description"] = description
        }
        let _: AnyJSON = try await performRpc("create_folder", params: params)
        // Invalidate cached folders
        let cacheKey = APICache.key("get_user_folders", params: nil)
        await cache.remove(cacheKey)
    }

    /// Edits an existing folder via Supabase RPC function
    public func editFolder(folderId: String, name: String, description: String?) async throws {
        let params: [String: Any?] = [
            "p_folder_id": folderId,
            "p_name": name,
            "p_description": description
        ]
        let _: AnyJSON = try await performRpc("edit_folder_function", params: params as [String: Any])
        // Invalidate cached folders
        let cacheKey = APICache.key("get_user_folders", params: nil)
        await cache.remove(cacheKey)
    }

    /// Uploads a file to Supabase Storage then saves metadata via RPC
    public func uploadFile(folderId: String, fileName: String, fileData: Data, fileType: String, fileSize: Int) async throws {
        let storagePath = "\(folderId)/\(fileName)"

        // Upload to storage bucket
        try await client.storage
            .from("files")
            .upload(storagePath, data: fileData, options: .init(contentType: fileType))

        // Get the public URL
        let publicURL = try client.storage
            .from("files")
            .getPublicURL(path: storagePath)

        // Save metadata via RPC
        let params: [String: Any?] = [
            "p_folder_id": folderId,
            "p_name": fileName,
            "p_file_url": publicURL.absoluteString,
            "p_file_type": fileType,
            "p_file_size": fileSize,
            "p_timespan": nil
        ]
        let _: AnyJSON = try await performRpc("upload_file_metadata", params: params as [String: Any])

        // Invalidate cached folder files
        let cacheKey = APICache.key("get_folder_files", params: ["p_folder_id": folderId])
        await cache.remove(cacheKey)
    }

    /// Removes a track like (unlike) via Supabase RPC function
    public func removeTrackLike(trackId: String) async throws {
        let _: AnyJSON = try await performRpc("toggle_track_like", params: ["p_track_id": trackId])
        // Invalidate cached likes
        let cacheKey = APICache.key("get_user_likes", params: nil)
        await cache.remove(cacheKey)
    }

    /// Deletes a file via Supabase RPC function
    public func deleteFile(fileId: String, folderId: String) async throws {
        let _: AnyJSON = try await performRpc("delete_file", params: ["p_file_id": fileId])
        // Invalidate cached folder files
        let cacheKey = APICache.key("get_folder_files", params: ["p_folder_id": folderId])
        await cache.remove(cacheKey)
    }

    /// Creates a new user service via Supabase RPC function
    public func createUserService(title: String, description: String, serviceType: String, price: Double, currency: String, deliveryTimeDays: Int?) async throws -> ApiUserService {
        let params: [String: Any?] = [
            "p_title": title,
            "p_description": description,
            "p_service_type": serviceType,
            "p_price": price,
            "p_currency": currency,
            "p_delivery_time_days": deliveryTimeDays
        ]
        let result: ApiUserService = try await performRpc("create_user_service", params: params as [String: Any])
        // Invalidate cached profile so services refresh
        return result
    }

    /// Updates an existing user service via Supabase RPC function
    public func updateUserService(serviceId: String, title: String?, description: String?, serviceType: String?, price: Double?, currency: String?, deliveryTimeDays: Int?, isActive: Bool?) async throws -> ApiUserService {
        let params: [String: Any?] = [
            "p_service_id": serviceId,
            "p_title": title,
            "p_description": description,
            "p_service_type": serviceType,
            "p_price": price,
            "p_currency": currency,
            "p_delivery_time_days": deliveryTimeDays,
            "p_is_active": isActive
        ]
        let result: ApiUserService = try await performRpc("update_user_service", params: params as [String: Any])
        return result
    }

    /// Updates the current user's profile via Supabase RPC function
    public func updateUserProfile(userId: String, username: String?, bio: String?, accountType: String?, location: String?, profileImageUrl: String?, bannerImageUrl: String?, tags: String?) async throws -> ApiUpdateProfileResponse {
        let params: [String: Any?] = [
            "p_username": username,
            "p_bio": bio,
            "p_account_type": accountType,
            "p_location": location,
            "p_profile_image_url": profileImageUrl,
            "p_banner_image_url": bannerImageUrl,
            "p_tags": tags
        ]
        let result: ApiUpdateProfileResponse = try await performRpc("update_user_profile", params: params as [String: Any])

        // Invalidate cached profile so next load fetches fresh data
        let cacheKey = APICache.key("get_user_profile", params: ["profile_id": userId])
        await cache.remove(cacheKey)

        return result
    }

    /// Uploads a user avatar to Supabase Storage and returns the public URL
    public func uploadAvatar(userId: String, imageData: Data) async throws -> URL {
        let storagePath = "\(userId).png"

        try await client.storage
            .from("user-avatars")
            .upload(storagePath, data: imageData, options: .init(contentType: "image/png", upsert: true))

        let publicURL = try client.storage
            .from("user-avatars")
            .getPublicURL(path: storagePath)

        return publicURL
    }

    /// Uploads a user banner to Supabase Storage and returns the public URL
    public func uploadBanner(userId: String, imageData: Data) async throws -> URL {
        let storagePath = "\(userId).png"

        try await client.storage
            .from("user-banners")
            .upload(storagePath, data: imageData, options: .init(contentType: "image/png", upsert: true))

        let publicURL = try client.storage
            .from("user-banners")
            .getPublicURL(path: storagePath)

        return publicURL
    }

    /// Fetches track detail from Supabase RPC function (cached 5 min)
    public func getTrackMetadata(trackId: String) async throws -> ApiTrackDetail {
        return try await cachedRpc("get_track_metadata", params: ["p_track_id": trackId], ttl: 300)
    }

    /// Fetches comments for a track from Supabase RPC function (cached 1 min)
    public func getTrackComments(trackId: String) async throws -> [ApiTrackComment] {
        return try await cachedRpc("get_track_comments", params: ["p_track_id": trackId], ttl: 60)
    }

    /// Posts a comment on a track via Supabase RPC function
    public func postComment(content: String, trackId: String, parentId: String? = nil) async throws {
        let params: [String: Any?] = [
            "p_content": content,
            "p_track_id": trackId,
            "p_parent_id": parentId // explicitly NULL when not replying
        ]
        let _: AnyJSON = try await performRpc("post_comment", params: params as [String: Any])
        // Invalidate cached comments for this track
        let cacheKey = APICache.key("get_track_comments", params: ["p_track_id": trackId])
        await cache.remove(cacheKey)
    }

    /// Uploads a post with media files to Supabase Storage then creates the post via RPC
    public func uploadPost(
        userId: String,
        title: String,
        description: String?,
        audioData: Data?,
        audioFileName: String?,
        videoData: Data?,
        videoFileName: String?,
        coverData: Data?,
        coverFileName: String?,
        postType: String
    ) async throws {
        print("[SupabaseService] uploadPost START")
        let normalizedUserId = userId.lowercased()
        print("[SupabaseService]   userId: \(userId) (normalized: \(normalizedUserId))")
        print("[SupabaseService]   title: \(title)")
        print("[SupabaseService]   description: \(description ?? "nil")")
        print("[SupabaseService]   postType: \(postType)")
        print("[SupabaseService]   audioData: \(audioData.map { "\($0.count) bytes" } ?? "nil"), fileName: \(audioFileName ?? "nil")")
        print("[SupabaseService]   videoData: \(videoData.map { "\($0.count) bytes" } ?? "nil"), fileName: \(videoFileName ?? "nil")")
        print("[SupabaseService]   coverData: \(coverData.map { "\($0.count) bytes" } ?? "nil"), fileName: \(coverFileName ?? "nil")")

        var audioUrl: String?
        var videoUrl: String?
        var coverUrl: String?

        // Upload audio to post-uploads/Posts/<user-id>/<file>
        if let audioData, let audioFileName {
            let path = "Posts/\(normalizedUserId)/\(audioFileName)"
            print("[SupabaseService]   Uploading audio to: \(path)")
            do {
                try await client.storage
                    .from("post-uploads")
                    .upload(path, data: audioData, options: .init(contentType: "audio/mpeg"))
                audioUrl = try client.storage
                    .from("post-uploads")
                    .getPublicURL(path: path)
                    .absoluteString
                print("[SupabaseService]   Audio uploaded OK: \(audioUrl ?? "")")
            } catch {
                print("[SupabaseService]   Audio upload FAILED: \(error)")
                throw error
            }
        }

        // Upload video to post-uploads/Videos/<user-id>/<file>
        if let videoData, let videoFileName {
            let path = "Videos/\(normalizedUserId)/\(videoFileName)"
            print("[SupabaseService]   Uploading video to: \(path)")
            do {
                try await client.storage
                    .from("post-uploads")
                    .upload(path, data: videoData, options: .init(contentType: "video/mp4"))
                videoUrl = try client.storage
                    .from("post-uploads")
                    .getPublicURL(path: path)
                    .absoluteString
                print("[SupabaseService]   Video uploaded OK: \(videoUrl ?? "")")
            } catch {
                print("[SupabaseService]   Video upload FAILED: \(error)")
                throw error
            }
        }

        // Upload cover art to post-uploads/Visuals/<user-id>/<file>
        if let coverData, let coverFileName {
            let path = "Visuals/\(normalizedUserId)/\(coverFileName)"
            print("[SupabaseService]   Uploading cover to: \(path)")
            do {
                try await client.storage
                    .from("post-uploads")
                    .upload(path, data: coverData, options: .init(contentType: "image/jpeg"))
                coverUrl = try client.storage
                    .from("post-uploads")
                    .getPublicURL(path: path)
                    .absoluteString
                print("[SupabaseService]   Cover uploaded OK: \(coverUrl ?? "")")
            } catch {
                print("[SupabaseService]   Cover upload FAILED: \(error)")
                throw error
            }
        }

        // Call RPC to create the track with the uploaded URLs
        // PostgREST requires ALL params to match the function signature
        let params: [String: Any] = [
            "p_title": title,
            "p_audio_url": audioUrl ?? NSNull(),
            "p_cover_url": coverUrl ?? NSNull(),
            "p_description": description ?? NSNull(),
            "p_visibility": "public",
            "p_location": NSNull(),
            "p_visual_url": videoUrl ?? NSNull(),
            "p_genre": NSNull(),
            "p_occupation": NSNull(),
            "p_credits": NSNull(),
            "p_metadata": NSNull()
        ]

        print("[SupabaseService]   Calling RPC create_track with params: \(params)")
        do {
            let _: AnyJSON = try await performRpc("create_track", params: params)
            print("[SupabaseService] uploadPost SUCCESS")
        } catch {
            print("[SupabaseService] uploadPost RPC FAILED: \(error)")
            throw error
        }
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

// MARK: - User Likes DTOs

public struct ApiLikeArtist: Codable, Sendable {
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

public struct ApiUserLike: Codable, Sendable, Identifiable {
    public var id: String { trackId }
    public let trackId: String
    public let title: String
    public let coverUrl: String?
    public let audioUrl: String?
    public let streams: Int?
    public let createdAt: String
    public let artist: ApiLikeArtist?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case title
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case streams
        case createdAt = "created_at"
        case artist
    }
}

// MARK: - Track Detail DTO

public struct ApiTrackDetailArtist: Codable, Sendable {
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?
    public let accountType: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
        case accountType = "account_type"
    }
}

public struct ApiTrackDetail: Codable, Sendable, Identifiable {
    public var id: String { trackId }
    public let trackId: String
    public let title: String
    public let description: String?
    public let genre: String?
    public let visibility: String?
    public let location: String?
    public let occupation: String?
    public let coverUrl: String?
    public let audioUrl: String?
    public let visualUrl: String?
    public let streams: Int?
    public let likes: Int?
    public let saves: Int?
    public let comments: Int?
    public let credits: [String: String]?
    public let metadata: [String: String]?
    public let createdAt: String?
    public let artist: ApiTrackDetailArtist?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case title, description, genre, visibility, location, occupation
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case visualUrl = "visual_url"
        case streams, likes, saves, comments, credits, metadata
        case createdAt = "created_at"
        case artist
    }
}

// MARK: - Track Comments DTOs

public struct ApiCommentUser: Codable, Sendable {
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

public struct ApiTrackComment: Codable, Sendable, Identifiable {
    public var id: String { commentId }
    public let commentId: String
    public let content: String
    public let createdAt: String
    public let trackId: String
    public let parentId: String?
    public let user: ApiCommentUser
    public let replies: [ApiTrackComment]?

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case content
        case createdAt = "created_at"
        case trackId = "track_id"
        case parentId = "parent_id"
        case user
        case replies
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
