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
    public static let baseURL = "https://api.volspire.com"
    public static let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhrem5rZHhoeW56cm13dXB1ZmF5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY2NzE3MDYsImV4cCI6MjA2MjI0NzcwNn0.yiRjLdzjAAAFJFfLT60ebqXeIF3mvj-UO8qtFq-Tyac"
    public static let redirectURL = "volspire://auth/callback"
}

// MARK: - Shared Supabase Client

public let supabaseClient = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.baseURL)!,
    supabaseKey: SupabaseConfig.apiKey
)

// MARK: - Home API Response Models

/// Mirrors the `get_home_tracks` RPC (and the web app's `HomeTracksData`),
/// which returns three track buckets.
public struct HomeTracksResponse: Codable, Sendable {
    public let popularTracks: [ApiHomeTrack]?
    public let demos: [ApiHomeTrack]?
    public let samples: [ApiHomeTrack]?

    enum CodingKeys: String, CodingKey {
        case popularTracks = "popular_tracks"
        case demos
        case samples
    }
}

public struct ApiHomeTrack: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String?
    public let coverUrl: String?
    public let audioUrl: String?
    public let streams: Int?
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artist
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case streams
        case durationMs = "duration_ms"
    }
}

/// An artist row from `get_explore_artists` (Explore "Artists" tab).
public struct ApiExploreArtist: Codable, Sendable, Identifiable {
    public var id: String { userId }
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?
    public let accountType: String?
    public let monthlyListeners: Int?
    public let followersCount: Int?
    public let tags: [String]?
    public let isFollowing: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
        case accountType = "account_type"
        case monthlyListeners = "monthly_listeners"
        case followersCount = "followers_count"
        case tags
        case isFollowing = "is_following"
    }
}

// MARK: - Messages Models

/// One row from `get_user_conversations`. Only the fields the iOS messages UI
/// consumes are decoded; everything optional so order/collab convo variants
/// (which carry extra columns) still decode cleanly.
public struct ApiConversation: Codable, Sendable, Identifiable {
    public var id: String { convoId }
    public let convoId: String
    public let title: String?
    public let type: String?
    public let lastMessageContent: String?
    public let lastMessageAt: String?
    public let lastMessageUserId: String?
    public let lastMessageType: String?
    public let unreadCount: Int?
    public let otherUserId: String?
    public let otherUsername: String?
    public let otherProfileImageUrl: String?
    public let archivedAt: String?
    /// Collab-request lifecycle (`pending` / `accepted` / `rejected`) — drives
    /// the messages list's Requests vs Archived classification.
    public let requestStatus: String?

    enum CodingKeys: String, CodingKey {
        case convoId = "convo_id"
        case title
        case type
        case lastMessageContent = "last_message_content"
        case lastMessageAt = "last_message_at"
        case lastMessageUserId = "last_message_user_id"
        case lastMessageType = "last_message_type"
        case unreadCount = "unread_count"
        case otherUserId = "other_user_id"
        case otherUsername = "other_username"
        case otherProfileImageUrl = "other_profile_image_url"
        case archivedAt = "archived_at"
        case requestStatus = "request_status"
    }
}

/// One row from `get_convo_messages` (returned oldest-first).
public struct ApiConvoMessage: Codable, Sendable, Identifiable {
    public var id: String { messageId }
    public let messageId: String
    public let convoId: String?
    public let userId: String?
    public let content: String?
    public let createdAt: String?
    public let attachment: Bool?
    public let attachmentUrl: String?
    public let attachmentType: String?
    public let attachmentName: String?
    public let username: String?
    public let profileImageUrl: String?
    public let messageType: String?
    /// Structured request payload (collab requests): `{ "track_ids": [...] }`.
    /// The referenced tracks are resolved separately via `getTracksByIds` and
    /// rendered as cards — the message `content` stays a plain caption.
    public let requestType: String?
    public let requestMetadata: RequestMetadata?
    /// Collab-request lifecycle — drives the inline Accept/Decline UI.
    public let requestId: String?
    public let requestStatus: String?     // "pending" | "accepted" | "rejected"
    public let requestFromUserId: String?

    public struct RequestMetadata: Codable, Sendable {
        public let trackIds: [String]?
        enum CodingKeys: String, CodingKey { case trackIds = "track_ids" }
    }

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case convoId = "convo_id"
        case userId = "user_id"
        case content
        case createdAt = "created_at"
        case attachment
        case attachmentUrl = "attachment_url"
        case attachmentType = "attachment_type"
        case attachmentName = "attachment_name"
        case username
        case profileImageUrl = "profile_image_url"
        case messageType = "message_type"
        case requestType = "request_type"
        case requestMetadata = "request_metadata"
        case requestId = "request_id"
        case requestStatus = "request_status"
        case requestFromUserId = "request_from_user_id"
    }
}

/// Compact, render-ready track for share cards (`get_tracks_by_ids`). Cover/audio
/// come back as bare storage paths — resolve via `StorageService` before use.
public struct ApiSharedTrack: Codable, Sendable, Identifiable {
    public var id: String { trackId }
    public let trackId: String
    public let title: String?
    public let coverUrl: String?
    public let audioUrl: String?
    public let artistUserId: String?
    public let artistUsername: String?
    public let artistImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case title
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case artistUserId = "artist_user_id"
        case artistUsername = "artist_username"
        case artistImageUrl = "artist_image_url"
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
    public let tags: [String]?
    public let followersCount: Int?
    public let monthlyListenersCount: Int
    public let trackCount: Int
    public let tracks: [ApiProfileTrack]
    public let services: [ApiUserService]
    /// Whether the signed-in viewer follows this profile. Computed server-side.
    public let isFollowing: Bool?
    /// Collaborator relationship from the viewer's perspective: `none` | `pending` | `accepted`.
    public let collaboratorStatus: String?
    /// Existing DM conversation id with this user, when one exists (drives "Message").
    public let collabConvoId: String?

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
        case isFollowing = "is_following"
        case collaboratorStatus = "collaborator_status"
        case collabConvoId = "collab_convo_id"
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
    public let tags: [String]?

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
    /// Optional seller-uploaded cover (bare storage path in `post-uploads`).
    public let coverUrl: String?
    /// Tailwind gradient class used as the cover fallback in the web app.
    public let gradient: String?
    /// `false` means the listing is private/owner-only (shown as a "Private" pill).
    public let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case serviceId = "service_id"
        case title, description, price, currency, gradient
        case serviceType = "service_type"
        case deliveryTimeDays = "delivery_time_days"
        case coverUrl = "cover_url"
        case isActive = "is_active"
    }
}

public struct ApiProfileTrack: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let coverUrl: String?
    public let audioUrl: String?
    public let streams: Int?
    public let hasVisual: Bool?
    /// `public` | `private` — own-profile rows surface a lock on private tracks.
    public let visibility: String?

    enum CodingKeys: String, CodingKey {
        case id, title, streams, visibility
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case hasVisual = "has_visual"
    }
}

/// A track owned by another artist where this profile's user is credited
/// (returned by `get_tracks_credited_to_user`). Cover/audio come back as bare
/// storage paths; resolve via `StorageService` before display/playback.
public struct ApiCreditedTrack: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String?
    public let artistId: String?
    public let artistProfileImageUrl: String?
    public let coverUrl: String?
    public let audioUrl: String?
    public let hasVisual: Bool?
    public let streams: Int?
    public let durationMs: Int?
    public let genre: String?
    /// The role this user was credited as (e.g. "Producer", "Mixing").
    public let role: String?
    /// True when the owning artist privatized/delisted the track. Only ever true
    /// for the credited user viewing their own profile (server owner-bypass).
    public let isUnavailable: Bool?
    /// `delisted` | `private` | nil — why an unavailable row is tombstoned.
    public let unavailableReason: String?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, streams, genre, role
        case artistId = "artist_id"
        case artistProfileImageUrl = "artist_profile_image_url"
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case hasVisual = "has_visual"
        case durationMs = "duration_ms"
        case isUnavailable = "is_unavailable"
        case unavailableReason = "unavailable_reason"
    }
}

/// A sample/preset/plugin pack owned by the profile user (`get_user_packs`).
/// `coverUrl` is a bare storage path in `post-uploads` when present.
public struct ApiUserPack: Codable, Sendable, Identifiable {
    public var id: String { packId }
    public let packId: String
    public let name: String
    public let packType: String?
    public let price: Double?
    public let fileCount: Int?
    public let formats: [String]?
    public let downloads: Int?
    public let gradient: String?
    public let coverUrl: String?
    public let isPublished: Bool?
    public let deprecated: Bool?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case name, price, formats, downloads, gradient, deprecated
        case packId = "pack_id"
        case packType = "pack_type"
        case fileCount = "file_count"
        case coverUrl = "cover_url"
        case isPublished = "is_published"
        case createdAt = "created_at"
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

    // Uploader info (optional — present when the API joins uploader profile data).
    public let uploaderUsername: String?
    public let uploaderProfileImageUrl: String?

    // Track-reference fields (optional — present when `type == "track"`).
    public let type: String?
    public let trackId: String?
    public let trackTitle: String?
    public let trackArtist: String?
    public let trackArtistId: String?
    public let trackCoverUrl: String?
    public let trackAudioUrl: String?
    public let trackVisibility: String?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case name
        case fileUrl = "file_url"
        case fileType = "file_type"
        case fileSize = "file_size"
        case timespan
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case uploaderUsername = "uploader_username"
        case uploaderProfileImageUrl = "uploader_profile_image_url"
        case type
        case trackId = "track_id"
        case trackTitle = "track_title"
        case trackArtist = "track_artist"
        case trackArtistId = "track_artist_id"
        case trackCoverUrl = "track_cover_url"
        case trackAudioUrl = "track_audio_url"
        case trackVisibility = "track_visibility"
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

/// One row from `get_workspace_activity` — a collaborator's recent action
/// (file upload / file comment / joining a folder) across the caller's
/// workspace folders.
public struct ApiWorkspaceActivity: Codable, Sendable, Identifiable {
    /// "upload" | "comment" | "join"
    public let activityType: String
    public let actorId: String
    public let actorUsername: String?
    /// Bare storage path or full URL — resolve via `StorageService.avatarUrl`.
    public let actorAvatar: String?
    public let folderId: String
    public let folderName: String?
    public let fileName: String?
    public let createdAt: String?

    /// No event PK comes back from the RPC — synthesize a stable identity.
    public var id: String { "\(activityType)-\(actorId)-\(createdAt ?? "")-\(fileName ?? "")" }

    enum CodingKeys: String, CodingKey {
        case activityType = "activity_type"
        case actorId = "actor_id"
        case actorUsername = "actor_username"
        case actorAvatar = "actor_avatar"
        case folderId = "folder_id"
        case folderName = "folder_name"
        case fileName = "file_name"
        case createdAt = "created_at"
    }
}

public struct ApiFolderMember: Codable, Sendable, Identifiable {
    public var id: String { userId }
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?
    public let role: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
        case role
    }
}

public struct ApiUserSearchResult: Codable, Sendable, Identifiable {
    public var id: String { userId }
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

// MARK: - Notification DTOs

public struct ApiNotificationActor: Codable, Sendable {
    public let userId: String?   // null when the actor row has no/deleted user (left join)
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
    public let action: String?          // activity_log.action is nullable
    public let objectType: String?
    public let objectId: String?
    public let objectTitle: String?
    public let contextType: String?
    public let contextId: String?
    public let contextPreview: String?
    public let isRead: Bool?            // activity_log.is_read is nullable
    public let actor: ApiNotificationActor?
    /// How many activity rows collapsed into this notification (> 1 only for
    /// aggregated likes/saves/shares).
    public let actionCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case action
        case objectType = "object_type"
        case objectId = "object_id"
        case objectTitle = "object_title"
        case contextType = "context_type"
        case contextId = "context_id"
        case contextPreview = "context_preview"
        case isRead = "is_read"
        case actor
        case actionCount = "action_count"
    }
}

/// The signed-in user's save/like state for a track (`get_track_interaction_status`).
public struct ApiTrackInteractionStatus: Codable, Sendable {
    public let isSaved: Bool
    public let isLiked: Bool

    enum CodingKeys: String, CodingKey {
        case isSaved = "is_saved"
        case isLiked = "is_liked"
    }
}

// MARK: - Notification Preferences

/// Per-event push/notification toggles (`user_notification_preferences`).
/// Mirrors the web settings page; every flag defaults to `true`.
public struct ApiNotificationPreferences: Codable, Sendable {
    public let newFollowers: Bool
    public let likes: Bool
    public let saves: Bool
    public let comments: Bool
    public let shares: Bool
    public let purchases: Bool
    public let uploads: Bool
    public let collaborations: Bool
    public let folders: Bool
    public let messages: Bool

    enum CodingKeys: String, CodingKey {
        case newFollowers = "new_followers"
        case likes, saves, comments, shares, purchases, uploads, collaborations, folders, messages
    }

    /// Flag lookup by the RPC column name (e.g. "likes", "new_followers").
    public func value(for key: String) -> Bool? {
        switch key {
        case "new_followers": return newFollowers
        case "likes": return likes
        case "saves": return saves
        case "comments": return comments
        case "shares": return shares
        case "purchases": return purchases
        case "uploads": return uploads
        case "collaborations": return collaborations
        case "folders": return folders
        case "messages": return messages
        default: return nil
        }
    }
}

// MARK: - Analytics

/// Per-track analytics for the signed-in creator (`get_my_track_analytics`),
/// ordered by total streams. `coverUrl` is a bare `post-uploads` path.
public struct ApiTrackAnalytics: Codable, Sendable, Identifiable {
    public var id: String { trackId }
    public let trackId: String
    public let title: String
    public let coverUrl: String?
    public let streams: Int
    public let uniqueListeners: Int
    public let avgListenTime: Double
    public let avgSeekCount: Double
    public let sources: [String: Int]
    public let dailyPlays: [DailyPlay]
    public let genre: String?
    public let createdAt: String?

    public struct DailyPlay: Codable, Sendable {
        public let date: String
        public let plays: Int
    }

    enum CodingKeys: String, CodingKey {
        case title, streams, sources, genre
        case trackId = "track_id"
        case coverUrl = "cover_url"
        case uniqueListeners = "unique_listeners"
        case avgListenTime = "avg_listen_time"
        case avgSeekCount = "avg_seek_count"
        case dailyPlays = "daily_plays"
        case createdAt = "created_at"
    }
}

/// Unread indicator counts (`get_unread_counts`): bell (activity), Inbox
/// (DMs), and pending seller actions.
public struct ApiUnreadCounts: Codable, Sendable {
    public let notifications: Int
    public let messages: Int
    public let serviceActions: Int

    enum CodingKeys: String, CodingKey {
        case notifications, messages
        case serviceActions = "service_actions"
    }
}

/// Creator engagement aggregates (`get_my_engagement_stats`): audience counts
/// with last-30-day deltas.
public struct ApiEngagementStats: Codable, Sendable {
    public let followersTotal: Int
    public let followers30d: Int
    public let likesTotal: Int
    public let likes30d: Int
    public let savesTotal: Int
    public let saves30d: Int
    public let commentsTotal: Int
    public let comments30d: Int
    public let shares30d: Int

    enum CodingKeys: String, CodingKey {
        case followersTotal = "followers_total"
        case followers30d = "followers_30d"
        case likesTotal = "likes_total"
        case likes30d = "likes_30d"
        case savesTotal = "saves_total"
        case saves30d = "saves_30d"
        case commentsTotal = "comments_total"
        case comments30d = "comments_30d"
        case shares30d = "shares_30d"
    }
}

// MARK: - Marketplace DTOs (get_explore_data)

public struct ApiMarketplaceUser: Codable, Sendable, Hashable {
    public let userId: String?
    public let username: String?
    public let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

public struct ApiMarketplacePack: Codable, Sendable, Identifiable, Hashable {
    public var id: String { packId }
    public let packId: String
    public let name: String
    public let packType: String?
    public let price: Double?
    public let downloads: Int?
    public let fileCount: Int?
    public let avgRating: Double?
    public let coverUrl: String?
    public let gradient: String?
    public let creator: ApiMarketplaceUser?

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case name
        case packType = "pack_type"
        case price
        case downloads
        case fileCount = "file_count"
        case avgRating = "avg_rating"
        case coverUrl = "cover_url"
        case gradient
        case creator
    }
}

public struct ApiMarketplaceService: Codable, Sendable, Identifiable, Hashable {
    public var id: String { serviceId }
    public let serviceId: String
    public let title: String
    public let serviceType: String?
    public let price: Double?
    public let deliveryTimeDays: Int?
    public let avgRating: Double?
    public let coverUrl: String?
    public let gradient: String?
    public let artist: ApiMarketplaceUser?

    enum CodingKeys: String, CodingKey {
        case serviceId = "service_id"
        case title
        case serviceType = "service_type"
        case price
        case deliveryTimeDays = "delivery_time_days"
        case avgRating = "avg_rating"
        case coverUrl = "cover_url"
        case gradient
        case artist
    }
}

public struct ApiExploreData: Codable, Sendable {
    public let packs: [ApiMarketplacePack]?
    public let services: [ApiMarketplaceService]?
}

// MARK: - Profile → Marketplace adapters

public extension ApiUserPack {
    /// Builds a marketplace-shaped pack (so a profile pack can navigate to the pack
    /// detail). `avgRating` isn't in the profile payload — the detail screen loads
    /// the full data on open anyway.
    func asMarketplacePack(creatorUserId: String?, creatorUsername: String?, creatorImageUrl: String?) -> ApiMarketplacePack {
        ApiMarketplacePack(
            packId: packId, name: name, packType: packType, price: price,
            downloads: downloads, fileCount: fileCount, avgRating: nil,
            coverUrl: coverUrl, gradient: gradient,
            creator: ApiMarketplaceUser(userId: creatorUserId, username: creatorUsername, profileImageUrl: creatorImageUrl)
        )
    }
}

public extension ApiUserService {
    /// Builds a marketplace-shaped service (so a profile service can navigate to the
    /// service detail).
    func asMarketplaceService(artistUserId: String?, artistUsername: String?, artistImageUrl: String?) -> ApiMarketplaceService {
        ApiMarketplaceService(
            serviceId: serviceId, title: title, serviceType: serviceType, price: price,
            deliveryTimeDays: deliveryTimeDays, avgRating: nil,
            coverUrl: coverUrl, gradient: gradient,
            artist: ApiMarketplaceUser(userId: artistUserId, username: artistUsername, profileImageUrl: artistImageUrl)
        )
    }
}

// MARK: - Search DTOs (search_all)

/// One track row from `search_all`. `coverUrl` / `audioUrl` are bare
/// `post-uploads` paths — resolve via StorageService before display/playback.
public struct ApiSearchTrack: Codable, Sendable, Identifiable {
    public var id: String { trackId }
    public let trackId: String
    public let title: String
    public let artist: String?
    public let artistId: String?
    public let coverUrl: String?
    public let audioUrl: String?
    public let streams: Int?
    public let durationMs: Int?
    public let genre: String?
    public let hasVisual: Bool?

    enum CodingKeys: String, CodingKey {
        case title, artist, genre, streams
        case trackId = "track_id"
        case artistId = "artist_id"
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case durationMs = "duration_ms"
        case hasVisual = "has_visual"
    }
}

/// Combined `search_all` payload. Packs/services/artists reuse the existing
/// marketplace/explore DTOs — the RPC returns a superset of their columns and
/// Codable ignores the extras.
public struct ApiSearchResults: Codable, Sendable {
    public let tracks: [ApiSearchTrack]
    public let services: [ApiMarketplaceService]
    public let packs: [ApiMarketplacePack]
    public let artists: [ApiExploreArtist]
}

// MARK: - Collab board (listings) DTOs

/// Board/card shape returned by `get_listings`.
public struct ApiListing: Codable, Sendable, Identifiable, Hashable {
    public var id: String { listingId }
    public let listingId: String
    public let category: String
    public let title: String
    public let description: String?
    public let tags: [String]?
    /// `attachments` should be a JSON array. Correctly-created listings store an
    /// array; legacy rows hold a double-encoded JSON *string* like "[]". Decoded
    /// flexibly either way, exposed via `attachments`.
    private let attachmentsValue: FlexibleListingAttachments?
    public let status: String?
    public let createdAt: String?
    public let author: ApiListingAuthor
    public let responseCount: Int?
    public let saveCount: Int?
    public let commentCount: Int?
    // Detail-only viewer flags (nil from the board feed; populated by `get_listing`).
    public let updatedAt: String?
    public let isAuthor: Bool?
    public let viewerHasSaved: Bool?
    public let viewerHasResponded: Bool?
    public let viewerConvoId: String?

    /// The attachment clips (empty if none).
    public var attachments: [ApiListingAttachment] { attachmentsValue?.items ?? [] }

    enum CodingKeys: String, CodingKey {
        case listingId = "listing_id"
        case category, title, description, tags, status, author
        case attachmentsValue = "attachments"
        case createdAt = "created_at"
        case responseCount = "response_count"
        case saveCount = "save_count"
        case commentCount = "comment_count"
        case updatedAt = "updated_at"
        case isAuthor = "is_author"
        case viewerHasSaved = "viewer_has_saved"
        case viewerHasResponded = "viewer_has_responded"
        case viewerConvoId = "viewer_convo_id"
    }
}

/// One flat comment on a listing (`get_listing_comments` / `post_listing_comment`).
public struct ApiListingComment: Codable, Sendable, Identifiable {
    public var id: String { commentId }
    public let commentId: String
    public let content: String
    public let createdAt: String?
    public let user: ApiListingAuthor

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case content
        case createdAt = "created_at"
        case user
    }
}

/// One responder to a listing (author-only, `get_listing_responses`).
public struct ApiListingResponse: Codable, Sendable, Identifiable {
    public var id: String { responseId }
    public let responseId: String
    public let convoId: String?
    public let createdAt: String?
    public let messagePreview: String?
    public let responder: ApiListingAuthor

    enum CodingKeys: String, CodingKey {
        case responseId = "response_id"
        case convoId = "convo_id"
        case createdAt = "created_at"
        case messagePreview = "message_preview"
        case responder
    }
}

public struct ApiListingAttachment: Codable, Sendable, Hashable {
    public let title: String?
    public let fileUrl: String?

    enum CodingKeys: String, CodingKey {
        case title
        case fileUrl = "file_url"
    }
}

/// Decodes a listing's `attachments` whether it arrives as a proper JSON array
/// (correct) or a legacy double-encoded JSON string like "[]".
struct FlexibleListingAttachments: Codable, Sendable, Hashable {
    let items: [ApiListingAttachment]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([ApiListingAttachment].self) {
            items = array
        } else if let string = try? container.decode(String.self),
                  let data = string.data(using: .utf8),
                  let array = try? JSONDecoder().decode([ApiListingAttachment].self, from: data) {
            items = array
        } else {
            items = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }
}

public struct ApiListingAuthor: Codable, Sendable, Hashable {
    public let userId: String
    public let username: String
    public let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

// MARK: - Marketplace detail DTOs (get_pack / get_service_detail)

/// Aggregate rating across all of a seller's packs + services.
public struct ApiSellerReputation: Codable, Sendable, Hashable {
    public let avgRating: Double?
    public let reviewCount: Int?

    enum CodingKeys: String, CodingKey {
        case avgRating = "avg_rating"
        case reviewCount = "review_count"
    }
}

public struct ApiReviewer: Codable, Sendable, Hashable {
    public let userId: String?
    public let username: String?
    public let profileImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

public struct ApiReview: Codable, Sendable, Hashable, Identifiable {
    public var id: String { reviewId }
    public let reviewId: String
    public let rating: Double?
    public let body: String?
    public let createdAt: String?
    public let verified: Bool?
    public let reviewer: ApiReviewer?

    enum CodingKeys: String, CodingKey {
        case reviewId = "review_id"
        case rating, body, verified, reviewer
        case createdAt = "created_at"
    }
}

/// One sample/file inside a pack.
public struct ApiPackFile: Codable, Sendable, Hashable, Identifiable {
    public var id: String { fileId }
    public let fileId: String
    public let name: String
    public let category: String?
    public let format: String?
    public let duration: Double?
    public let fileUrl: String?
    public let fileSize: Int?
    public let isPreview: Bool

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case name, category, format, duration
        case fileUrl = "file_url"
        case fileSize = "file_size"
        case isPreview = "is_preview"
    }
}

public struct ApiPackDetail: Codable, Sendable {
    public let packId: String
    public let name: String
    public let packType: String?
    public let description: String?
    public let price: Double?
    public let currency: String?
    public let formats: [String]?
    public let coverUrl: String?
    public let gradient: String?
    public let tags: [String]?
    public let fileCount: Int?
    public let downloads: Int?
    public let likes: Int?
    public let saves: Int?
    public let avgRating: Double?
    public let reviewCount: Int?
    public let createdAt: String?
    public let ownerId: String?
    public let creatorUsername: String?
    public let creatorImage: String?
    public let sellerReputation: ApiSellerReputation?
    public let files: [ApiPackFile]?
    public let reviews: [ApiReview]?
    public let isPublished: Bool?

    enum CodingKeys: String, CodingKey {
        case name, description, price, currency, formats, tags, downloads, likes, saves, files, reviews, gradient
        case packId = "pack_id"
        case packType = "pack_type"
        case coverUrl = "cover_url"
        case fileCount = "file_count"
        case avgRating = "avg_rating"
        case reviewCount = "review_count"
        case createdAt = "created_at"
        case ownerId = "owner_id"
        case creatorUsername = "creator_username"
        case creatorImage = "creator_image"
        case sellerReputation = "seller_reputation"
        case isPublished = "is_published"
    }
}

/// A service pricing tier (Basic / Standard / Pro).
public struct ApiServicePackage: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let price: Double?
    public let delivery: Int?
    public let revisions: Int?
    public let features: [String]?
}

public struct ApiServiceProcessStep: Codable, Sendable, Hashable, Identifiable {
    public var id: String { step }
    public let step: String
    public let description: String?
}

public struct ApiServiceFaq: Codable, Sendable, Hashable, Identifiable {
    public var id: String { q }
    public let q: String
    public let a: String?
}

public struct ApiServiceArtist: Codable, Sendable, Hashable {
    public let userId: String?
    public let username: String?
    public let profileImageUrl: String?
    public let bio: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username, bio
        case profileImageUrl = "profile_image_url"
    }
}

public struct ApiServiceDetail: Codable, Sendable {
    public let serviceId: String
    public let title: String
    public let serviceType: String?
    public let longDescription: String?
    public let price: Double?
    public let currency: String?
    public let deliveryTimeDays: Int?
    public let revisions: Int?
    public let tags: [String]?
    public let coverUrl: String?
    public let gradient: String?
    public let avgRating: Double?
    public let reviewCount: Int?
    public let likes: Int?
    public let saves: Int?
    public let createdAt: String?
    public let artist: ApiServiceArtist?
    public let packages: [ApiServicePackage]?
    public let process: [ApiServiceProcessStep]?
    public let deliverables: [String]?
    public let faqs: [ApiServiceFaq]?
    public let portfolio: [ApiListingAttachment]?
    public let sellerReputation: ApiSellerReputation?
    public let reviews: [ApiReview]?

    enum CodingKeys: String, CodingKey {
        case title, price, currency, revisions, tags, likes, saves, artist, packages, process, deliverables, faqs, reviews, gradient, portfolio
        case serviceId = "service_id"
        case serviceType = "service_type"
        case longDescription = "long_description"
        case deliveryTimeDays = "delivery_time_days"
        case coverUrl = "cover_url"
        case avgRating = "avg_rating"
        case reviewCount = "review_count"
        case createdAt = "created_at"
        case sellerReputation = "seller_reputation"
    }
}

// MARK: - Playlist DTOs

public struct ApiPlaylist: Codable, Sendable, Identifiable {
    public var id: String { playlistId }
    public let playlistId: String
    public let title: String
    public let description: String?
    public let coverUrl: String?
    public let visibility: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case playlistId = "playlist_id"
        case title, description, visibility
        case coverUrl = "cover_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case trackCount = "track_count"
    }
}

public struct ApiPlaylistTrack: Codable, Sendable, Identifiable {
    public var id: String { trackId }
    public let trackId: String
    public let title: String
    public let coverUrl: String?
    public let audioUrl: String?
    public let durationMs: Int?
    public let genre: String?
    public let createdBy: String?
    public let artistUsername: String?
    public let artistAvatarUrl: String?
    public let position: Int?
    public let addedAt: String?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case title, genre, position
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case durationMs = "duration_ms"
        case createdBy = "created_by"
        case artistUsername = "artist_username"
        case artistAvatarUrl = "artist_avatar_url"
        case addedAt = "added_at"
    }
}

public struct ApiPlaylistDetail: Codable, Sendable, Identifiable {
    public var id: String { playlistId }
    public let playlistId: String
    public let title: String
    public let description: String?
    public let coverUrl: String?
    public let visibility: String?
    public let ownerId: String?
    public let ownerUsername: String?
    public let ownerAvatarUrl: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let tracks: [ApiPlaylistTrack]?

    enum CodingKeys: String, CodingKey {
        case playlistId = "playlist_id"
        case title, description, visibility, tracks
        case coverUrl = "cover_url"
        case ownerId = "owner_id"
        case ownerUsername = "owner_username"
        case ownerAvatarUrl = "owner_avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Supabase Service Protocol

public protocol SupabaseServiceProtocol: Sendable {
    func getHomeTracks() async throws -> HomeTracksResponse
    func getFollowingFeed() async throws -> [ApiHomeTrack]
    func getExploreTracksFeed(seed: Int) async throws -> [ApiHomeTrack]
    func getExploreArtists() async throws -> [ApiExploreArtist]
    func getUserProfile(userId: String) async throws -> ApiUserProfile
    func getTracksCreditedToUser(userId: String) async throws -> [ApiCreditedTrack]
    func getUserPacks(userId: String) async throws -> [ApiUserPack]
    func getUserLikes() async throws -> [ApiUserLike]
    func getUserLibrary() async throws -> [ApiUserLike]
    func unsaveTrack(trackId: String) async throws
    func getUserNotifications() async throws -> [ApiNotification]
    func markNotificationsRead() async throws
    func getNotificationPreferences() async throws -> ApiNotificationPreferences
    func updateNotificationPreference(key: String, value: Bool) async throws -> ApiNotificationPreferences
    func getMyTrackAnalytics() async throws -> [ApiTrackAnalytics]
    func getUserFolders() async throws -> [ApiUserFolder]
    func getFolderFiles(folderId: String) async throws -> [ApiFolderFile]
    func getUserConversations(limit: Int, offset: Int) async throws -> [ApiConversation]
    func getConvoMessages(convoId: String, limit: Int, offset: Int) async throws -> [ApiConvoMessage]
    func sendMessage(convoId: String, content: String) async throws -> String
    func markConvoRead(convoId: String) async throws
    func toggleFollow(targetUser: String) async throws
    func sendCollabRequest(targetId: String, message: String, trackIds: [String]?) async throws
    @discardableResult
    func createFolder(name: String, description: String?) async throws -> String
    func editFolder(folderId: String, name: String, description: String?) async throws
    func uploadFile(folderId: String, fileName: String, fileData: Data, fileType: String, fileSize: Int) async throws
    func deleteFile(fileId: String, folderId: String) async throws
    func createUserService(title: String, description: String, serviceType: String, price: Double, currency: String, deliveryTimeDays: Int?) async throws -> ApiUserService
    func updateUserService(serviceId: String, title: String?, description: String?, serviceType: String?, price: Double?, currency: String?, deliveryTimeDays: Int?, isActive: Bool?) async throws -> ApiUserService
    func updateUserProfile(userId: String, username: String?, bio: String?, accountType: String?, location: String?, profileImageUrl: String?, bannerImageUrl: String?, tags: [String]?) async throws -> ApiUpdateProfileResponse
    func uploadAvatar(userId: String, imageData: Data) async throws -> URL
    func uploadBanner(userId: String, imageData: Data) async throws -> URL
    func getTrackInteractionStatus(trackId: String) async throws -> ApiTrackInteractionStatus
    func likeTrack(trackId: String) async throws
    func unlikeTrack(trackId: String) async throws
    func saveTrack(trackId: String) async throws
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

    /// The signed-in user's id from the in-memory session (nil if signed out).
    /// Lowercased to match Postgres UUID text (Swift's `uuidString` is uppercase),
    /// so it compares equal to DB-sourced user ids.
    public var currentUserId: String? {
        client.auth.currentUser?.id.uuidString.lowercased()
    }

    // MARK: - Public Methods

    /// Fetches home tracks data from Supabase RPC function (cached 5 min)
    public func getHomeTracks() async throws -> HomeTracksResponse {
        return try await cachedRpc("get_home_tracks", params: nil, ttl: 300)
    }

    /// Tracks from artists the current user follows (Explore "Following" tab).
    public func getFollowingFeed() async throws -> [ApiHomeTrack] {
        return try await cachedRpc("get_following_feed", params: ["p_limit": 30, "p_offset": 0], ttl: 60)
    }

    /// General track feed (Explore "Tracks" tab). `seed` shuffles the ordering
    /// server-side — mirror the web by passing a fresh random seed per session
    /// so the recommendations vary instead of returning the same order forever.
    /// Cached per-seed, so the same seed reuses results but a new seed refetches.
    public func getExploreTracksFeed(seed: Int) async throws -> [ApiHomeTrack] {
        return try await cachedRpc("get_home_feed", params: ["p_seed": seed, "p_limit": 30, "p_offset": 0], ttl: 120)
    }

    /// Artists to explore (Explore "Artists" tab).
    public func getExploreArtists() async throws -> [ApiExploreArtist] {
        return try await cachedRpc("get_explore_artists", params: ["p_limit": 30, "p_offset": 0], ttl: 120)
    }

    // MARK: - Messages

    /// The signed-in user's conversation list, most-recent first. Uncached — the
    /// inbox needs to reflect new messages and read state immediately.
    public func getUserConversations(limit: Int = 30, offset: Int = 0) async throws -> [ApiConversation] {
        return try await performRpc("get_user_conversations", params: ["p_limit": limit, "p_offset": offset])
    }

    /// Messages for a conversation, returned oldest-first (`p_offset` pages backwards).
    public func getConvoMessages(convoId: String, limit: Int = 50, offset: Int = 0) async throws -> [ApiConvoMessage] {
        return try await performRpc("get_convo_messages", params: ["p_convo_id": convoId, "p_limit": limit, "p_offset": offset])
    }

    /// Resolves shared track ids (e.g. from a collab request's `request_metadata`)
    /// into render-ready cards. Order-preserving; private tracks resolve only for
    /// their owner.
    public func getTracksByIds(_ ids: [String]) async throws -> [ApiSharedTrack] {
        guard !ids.isEmpty else { return [] }
        return try await performRpc("get_tracks_by_ids", params: ["p_track_ids": ids])
    }

    /// Accepts a pending request (collab request). Only the recipient may; sets
    /// `requests.status = 'accepted'` and syncs the collaborator relationship.
    public func acceptRequest(requestId: String) async throws {
        try await executeRpc("accept_request", params: ["p_request_id": requestId])
    }

    /// Declines a pending request (collab request) — recipient only.
    public func rejectRequest(requestId: String) async throws {
        try await executeRpc("reject_request", params: ["p_request_id": requestId])
    }

    /// Sends a text message; returns the new message id.
    public func sendMessage(convoId: String, content: String) async throws -> String {
        return try await performRpc("send_message", params: ["p_convo_id": convoId, "p_content": content])
    }

    /// Uploads a message attachment to the private `message-attachments` bucket and
    /// returns its storage path (mirrors the web app's path scheme).
    public func uploadMessageAttachment(convoId: String, userId: String, fileName: String, data: Data, fileType: String) async throws -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "bin" : ext
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let path = "\(convoId)/\(userId)/\(stamp)-\(UUID().uuidString).\(safeExt)"
        try await client.storage
            .from("message-attachments")
            .upload(path, data: data, options: .init(contentType: fileType))
        return path
    }

    /// Sends a message carrying an attachment (stored at `fileUrl`); returns the new id.
    public func sendMessageWithAttachment(convoId: String, content: String, fileUrl: String, fileType: String, fileName: String, fileSize: Int) async throws -> String {
        let params: [String: Any] = [
            "p_convo_id": convoId,
            "p_content": content,
            "p_file_url": fileUrl,
            "p_file_type": fileType,
            "p_metadata": ["name": fileName, "size": fileSize] as [String: Any],
        ]
        return try await performRpc("send_message_with_attachment", params: params)
    }

    /// Marks every message in a conversation as read for the calling user.
    public func markConvoRead(convoId: String) async throws {
        // Void-returning RPC — empty body, must not be decoded. (Previously
        // decoded as AnyJSON, which always threw after the server applied the
        // mark; callers' `try?` hid it.)
        try await executeRpc("mark_convo_read", params: ["p_convo_id": convoId])
    }

    /// Fetches a user profile from Supabase RPC function (cached 5 min)
    public func getUserProfile(userId: String) async throws -> ApiUserProfile {
        return try await cachedRpc("get_user_profile", params: ["profile_id": userId], ttl: 300)
    }

    /// Drops the cached profile + profile-tab payloads for `userId` so the next
    /// fetch is fresh — called after publishing a track, and by the profile's
    /// pull-to-refresh.
    public func invalidateProfile(userId: String) async {
        await cache.remove(APICache.key("get_user_profile", params: ["profile_id": userId]))
        await cache.remove(APICache.key("get_tracks_credited_to_user", params: ["p_user_id": userId]))
        await cache.remove(APICache.key("get_user_packs", params: ["p_user_id": userId]))
    }

    /// Fetches every publicly-visible track where `userId` is credited, with the
    /// role they were credited as ("Featured On" tab). Cached 2 min.
    public func getTracksCreditedToUser(userId: String) async throws -> [ApiCreditedTrack] {
        return try await cachedRpc("get_tracks_credited_to_user", params: ["p_user_id": userId], ttl: 120)
    }

    /// Fetches the sample/preset/plugin packs owned by `userId` ("Packs" tab). Cached 2 min.
    public func getUserPacks(userId: String) async throws -> [ApiUserPack] {
        return try await cachedRpc("get_user_packs", params: ["p_user_id": userId], ttl: 120)
    }

    /// Fetches the current user's liked tracks (cached 1 min)
    public func getUserLikes() async throws -> [ApiUserLike] {
        return try await cachedRpc("get_user_likes", params: nil, ttl: 60)
    }

    /// Fetches the user's saved library (`user_saves`), matching the web app's "Saved" tab.
    public func getUserLibrary() async throws -> [ApiUserLike] {
        return try await cachedRpc("get_user_library", params: nil, ttl: 60)
    }

    /// Fetches the current user's notifications (cached 30s)
    public func getUserNotifications() async throws -> [ApiNotification] {
        return try await cachedRpc("get_user_notifications", params: nil, ttl: 30)
    }

    /// Marks all of the signed-in user's notifications as read.
    public func markNotificationsRead() async throws {
        // Void-returning RPC — empty body, must not be decoded.
        try await executeRpc("mark_notifications_read", params: nil)
    }

    /// Fetches the signed-in user's notification toggles (cached 1 min).
    public func getNotificationPreferences() async throws -> ApiNotificationPreferences {
        return try await cachedRpc("get_notification_preferences", params: nil, ttl: 60)
    }

    /// Fetches per-track analytics for the signed-in creator (cached 2 min).
    public func getMyTrackAnalytics() async throws -> [ApiTrackAnalytics] {
        return try await cachedRpc("get_my_track_analytics", params: nil, ttl: 120)
    }

    /// Creator engagement aggregates — followers / likes / saves / comments
    /// (totals + last-30-day deltas) and 30-day shares (`get_my_engagement_stats`).
    public func getMyEngagementStats() async throws -> ApiEngagementStats {
        return try await cachedRpc("get_my_engagement_stats", params: nil, ttl: 120)
    }

    /// In-app unread indicator counts (`get_unread_counts` — the same RPC the
    /// web uses for its dots). Never cached: it drives live badges.
    public func getUnreadCounts() async throws -> ApiUnreadCounts {
        return try await performRpc("get_unread_counts")
    }

    /// Flips a single notification toggle (the RPC coalesces every other column
    /// to its current value), returning the full updated preferences.
    public func updateNotificationPreference(key: String, value: Bool) async throws -> ApiNotificationPreferences {
        let result: ApiNotificationPreferences = try await performRpc(
            "update_notification_preferences", params: ["p_\(key)": value]
        )
        await cache.remove(APICache.key("get_notification_preferences", params: nil))
        return result
    }

    /// Fetches the current user's folders (cached 1 min)
    public func getUserFolders() async throws -> [ApiUserFolder] {
        return try await cachedRpc("get_user_folders", params: nil, ttl: 60)
    }

    /// Collaborators' actions from the past month (uploads / comments / joins)
    /// across the caller's workspace folders (`get_workspace_activity`, newest
    /// first; excludes the caller's own actions). Uncached — it's "what's new".
    public func getWorkspaceActivity(limit: Int = 30) async throws -> [ApiWorkspaceActivity] {
        return try await performRpc("get_workspace_activity", params: ["p_limit": limit])
    }

    /// Marketplace browse data — public packs + services (`get_explore_data`).
    public func getExploreData() async throws -> ApiExploreData {
        return try await cachedRpc("get_explore_data", params: nil, ttl: 60)
    }

    /// The public collab-board feed (`get_listings`). `category` nil = all.
    public func getListings(category: String?, limit: Int = 100, offset: Int = 0) async throws -> [ApiListing] {
        return try await performRpc("get_listings", params: [
            "p_category": category ?? NSNull(),
            "p_limit": limit,
            "p_offset": offset,
        ])
    }

    /// A specific user's collab-board listings (`get_user_listings`) — same shape as
    /// the board feed. Includes the owner's non-open listings when they're viewing.
    public func getUserListings(userId: String) async throws -> [ApiListing] {
        return try await performRpc("get_user_listings", params: ["p_user_id": userId])
    }

    /// Full listing detail with viewer flags (`get_listing`).
    public func getListing(listingId: String) async throws -> ApiListing {
        return try await performRpc("get_listing", params: ["p_listing_id": listingId])
    }

    /// Responds to a listing — sends `message` to the author and returns the
    /// resulting conversation id (`respond_to_listing`).
    public func respondToListing(listingId: String, message: String) async throws -> String {
        return try await performRpc("respond_to_listing", params: ["p_listing_id": listingId, "p_message": message])
    }

    public func saveListing(listingId: String) async throws {
        try await executeRpc("save_listing", params: ["p_listing_id": listingId])
    }

    public func unsaveListing(listingId: String) async throws {
        try await executeRpc("unsave_listing", params: ["p_listing_id": listingId])
    }

    public func getListingComments(listingId: String) async throws -> [ApiListingComment] {
        return try await performRpc("get_listing_comments", params: ["p_listing_id": listingId])
    }

    public func postListingComment(listingId: String, content: String) async throws -> ApiListingComment {
        return try await performRpc("post_listing_comment", params: ["p_listing_id": listingId, "p_content": content])
    }

    public func deleteListingComment(commentId: String) async throws {
        try await executeRpc("delete_listing_comment", params: ["p_comment_id": commentId])
    }

    /// Author-only: the people who've responded to a listing (`get_listing_responses`).
    public func getListingResponses(listingId: String) async throws -> [ApiListingResponse] {
        return try await performRpc("get_listing_responses", params: ["p_listing_id": listingId])
    }

    /// Author-only: open/close a listing (`update_listing`; other fields keep).
    public func updateListingStatus(listingId: String, status: String) async throws {
        try await executeRpc("update_listing", params: ["p_listing_id": listingId, "p_status": status])
    }

    /// Author-only: permanently delete a listing (`delete_listing`).
    public func deleteListing(listingId: String) async throws {
        try await executeRpc("delete_listing", params: ["p_listing_id": listingId])
    }

    /// Full detail for a marketplace sound pack (`get_pack`).
    public func getPack(packId: String) async throws -> ApiPackDetail {
        return try await performRpc("get_pack", params: ["p_pack_id": packId])
    }

    /// Full detail for a marketplace service (`get_service_detail`).
    public func getServiceDetail(serviceId: String) async throws -> ApiServiceDetail {
        return try await performRpc("get_service_detail", params: ["p_service_id": serviceId])
    }

    // MARK: - Playlists

    /// The signed-in user's playlists (`get_user_playlists`).
    public func getUserPlaylists() async throws -> [ApiPlaylist] {
        return try await performRpc("get_user_playlists")
    }

    /// A single playlist with its ordered tracks (`get_playlist`).
    public func getPlaylist(playlistId: String) async throws -> ApiPlaylistDetail {
        return try await performRpc("get_playlist", params: ["p_playlist_id": playlistId])
    }

    /// Creates a playlist (`create_playlist`).
    /// Creates a playlist and returns the new playlist's id (so a cover can be
    /// uploaded to it afterward). `create_playlist` returns `{ playlist_id }`.
    @discardableResult
    public func createPlaylist(title: String, description: String? = nil, visibility: String = "public") async throws -> String {
        var params: [String: Any] = ["p_title": title, "p_visibility": visibility]
        if let description, !description.trimmingCharacters(in: .whitespaces).isEmpty {
            params["p_description"] = description
        }
        let created: CreatedPlaylist = try await performRpc("create_playlist", params: params)
        return created.playlistId
    }

    private struct CreatedPlaylist: Decodable {
        let playlistId: String
        enum CodingKeys: String, CodingKey { case playlistId = "playlist_id" }
    }

    /// Updates a playlist's metadata (`update_playlist`). Owner-only; nil fields are left unchanged.
    public func updatePlaylist(playlistId: String, title: String? = nil, description: String? = nil, visibility: String? = nil, coverUrl: String? = nil) async throws {
        var params: [String: Any] = ["p_playlist_id": playlistId]
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            params["p_title"] = title
        }
        if let description {
            params["p_description"] = description
        }
        if let visibility {
            params["p_visibility"] = visibility
        }
        if let coverUrl {
            params["p_cover_url"] = coverUrl
        }
        try await executeRpc("update_playlist", params: params)
    }

    /// Uploads a playlist cover to the public `post-uploads` bucket and returns its public URL.
    /// Path's second segment must be the uploader's auth id (storage RLS); a timestamp keeps
    /// each save's URL unique so caches refetch the new image.
    public func uploadPlaylistCover(playlistId: String, userId: String, imageData: Data) async throws -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let path = "Playlists/\(userId.lowercased())/\(playlistId)-\(stamp).jpg"
        try await client.storage
            .from("post-uploads")
            .upload(path, data: imageData, options: .init(contentType: "image/jpeg"))
        return try client.storage
            .from("post-uploads")
            .getPublicURL(path: path)
            .absoluteString
    }

    /// Deletes a playlist (`delete_playlist`).
    public func deletePlaylist(playlistId: String) async throws {
        try await executeRpc("delete_playlist", params: ["p_playlist_id": playlistId])
    }

    /// Adds a track to a playlist (`add_track_to_playlist`).
    public func addTrackToPlaylist(playlistId: String, trackId: String) async throws {
        try await executeRpc("add_track_to_playlist", params: ["p_playlist_id": playlistId, "p_track_id": trackId])
    }

    /// Removes a track from a playlist (`remove_track_from_playlist`).
    public func removeTrackFromPlaylist(playlistId: String, trackId: String) async throws {
        try await executeRpc("remove_track_from_playlist", params: ["p_playlist_id": playlistId, "p_track_id": trackId])
    }

    /// Ids of the caller's playlists that already contain the given track
    /// (`get_playlists_for_track`) — used to pre-check the "Add to playlist" rows.
    public func getPlaylistsForTrack(trackId: String) async throws -> [String] {
        return try await performRpc("get_playlists_for_track", params: ["p_track_id": trackId])
    }

    /// Fetches files in a folder from Supabase RPC function (cached 1 min)
    public func getFolderFiles(folderId: String) async throws -> [ApiFolderFile] {
        return try await cachedRpc("get_folder_files", params: ["p_folder_id": folderId], ttl: 60)
    }

    /// Adds a track to a workspace folder. Already-in-folder (unique violation) is
    /// treated as success, mirroring the web app. `add_track_to_folder` returns void.
    public func addTrackToFolder(trackId: String, folderId: String) async throws {
        let params: [String: Any?] = ["p_folder_id": folderId, "p_track_id": trackId]
        do {
            try await executeRpc("add_track_to_folder", params: params as [String: Any])
        } catch {
            let msg = error.localizedDescription.lowercased()
            guard msg.contains("duplicate") || msg.contains("unique") || msg.contains("already") else { throw error }
        }
        let cacheKey = APICache.key("get_folder_files", params: ["p_folder_id": folderId])
        await cache.remove(cacheKey)
    }

    /// Removes a track from a workspace folder (`remove_track_from_folder`).
    public func removeTrackFromFolder(trackId: String, folderId: String) async throws {
        try await executeRpc("remove_track_from_folder", params: ["p_folder_id": folderId, "p_track_id": trackId])
        await cache.remove(APICache.key("get_folder_files", params: ["p_folder_id": folderId]))
    }

    /// Ids of the folders the caller can access that already contain the track
    /// (`get_folders_for_track`) — used to pre-check the "Add to Workspace" rows.
    public func getFoldersForTrack(trackId: String) async throws -> [String] {
        return try await performRpc("get_folders_for_track", params: ["p_track_id": trackId])
    }

    /// Toggles follow/unfollow for a user
    public func toggleFollow(targetUser: String) async throws {
        let _: AnyJSON = try await performRpc("toggle_user_follow", params: ["target_user": targetUser])
        // Invalidate cached profile for this user
        let cacheKey = APICache.key("get_user_profile", params: ["profile_id": targetUser])
        await cache.remove(cacheKey)
    }

    /// Sends a collaboration request to an artist (`send_collab_request`), optionally
    /// attaching up to 3 of the sender's tracks. The DB raises `collab_rate_limited`
    /// (one request per artist per week) and `collab_attachment_cap` — surfaced via
    /// the thrown error's text so callers can show a friendly message.
    public func sendCollabRequest(targetId: String, message: String, trackIds: [String]? = nil) async throws {
        let params: [String: Any] = [
            "p_target_id": targetId,
            "p_message": message,
            "p_track_ids": (trackIds?.isEmpty == false ? trackIds! : NSNull()) as Any
        ]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: params)
            let anyJSON = try JSONDecoder().decode(AnyJSON.self, from: jsonData)
            _ = try await client.rpc("send_collab_request", params: anyJSON).execute()
        } catch {
            // Keep the raw error text (PostgrestError includes its `message`) so the
            // caller can detect specific guards like `collab_rate_limited`.
            print("[SupabaseService] send_collab_request ERROR: \(error)")
            throw SupabaseError.serverError("\(error)")
        }
        // The viewer's collaborator status changed — drop the cached profile.
        await cache.remove(APICache.key("get_user_profile", params: ["profile_id": targetId]))
    }

    /// Creates a new folder and returns its id — `create_folder` returns
    /// `{ success, folder_id }`. `p_description` is always sent: the RPC
    /// declares it without a default, so omitting it wouldn't resolve.
    @discardableResult
    public func createFolder(name: String, description: String?) async throws -> String {
        let params: [String: Any] = [
            "p_name": name,
            "p_description": description ?? ""
        ]
        let created: CreatedFolder = try await performRpc("create_folder", params: params)
        // Invalidate cached folders
        let cacheKey = APICache.key("get_user_folders", params: nil)
        await cache.remove(cacheKey)
        return created.folderId
    }

    private struct CreatedFolder: Decodable {
        let folderId: String
        enum CodingKeys: String, CodingKey { case folderId = "folder_id" }
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

    /// Renames/updates a folder (`update_folder`). Owner-only; `description` is
    /// overwritten, so pass the current value to preserve it.
    public func updateFolder(folderId: String, name: String, description: String?) async throws {
        var params: [String: Any] = ["p_folder_id": folderId, "p_name": name]
        if let description { params["p_description"] = description }
        let _: AnyJSON = try await performRpc("update_folder", params: params)
        await cache.remove(APICache.key("get_user_folders", params: nil))
    }

    /// Deletes a folder and its contents (`delete_folder`). Owner-only.
    public func deleteFolder(folderId: String) async throws {
        try await executeRpc("delete_folder", params: ["p_folder_id": folderId])
        await cache.remove(APICache.key("get_user_folders", params: nil))
    }

    // MARK: - Folder members (collaboration)

    /// Members of a folder, including the owner (`get_folder_members`).
    public func getFolderMembers(folderId: String) async throws -> [ApiFolderMember] {
        try await performRpc("get_folder_members", params: ["p_folder_id": folderId])
    }

    /// Adds a collaborator by username (`add_folder_member`). Owner/admin-only.
    public func addFolderMember(folderId: String, username: String, role: String) async throws {
        let _: AnyJSON = try await performRpc("add_folder_member", params: [
            "p_folder_id": folderId, "p_username": username, "p_role": role
        ])
    }

    /// Removes a collaborator (`remove_folder_member`). Owner/admin-only.
    public func removeFolderMember(folderId: String, targetUserId: String) async throws {
        try await executeRpc("remove_folder_member", params: ["p_folder_id": folderId, "p_target_user_id": targetUserId])
    }

    /// Changes a collaborator's role (`update_folder_member_role`). Owner/admin-only.
    public func updateFolderMemberRole(folderId: String, targetUserId: String, role: String) async throws {
        try await executeRpc("update_folder_member_role", params: [
            "p_folder_id": folderId, "p_target_user_id": targetUserId, "p_role": role
        ])
    }

    /// Searches users by username prefix (`search_users`).
    public func searchUsers(query: String, limit: Int = 8) async throws -> [ApiUserSearchResult] {
        try await performRpc("search_users", params: ["p_query": query, "p_limit": limit])
    }

    /// Your collaborators — people you've worked with — for the folder member
    /// picker (mirrors the web's `get_my_collaborators`, used by the share-folder modal).
    public func getMyCollaborators() async throws -> [ApiUserSearchResult] {
        try await performRpc("get_my_collaborators")
    }

    /// Full-catalog search (`search_all`) — tracks, artists, packs, services.
    /// Matches the web app's `/api/search` (which calls the same RPC, limit 20).
    public func searchAll(query: String, limit: Int = 20) async throws -> ApiSearchResults {
        try await performRpc("search_all", params: ["p_query": query, "p_limit": limit])
    }

    /// Uploads a file to Supabase Storage then saves metadata via RPC.
    /// The storage key is a fresh UUID — the same scheme as
    /// `addAttachmentToFolder` and the web. Raw display names made invalid or
    /// colliding storage keys (spaces/brackets/$; re-uploading a name 409'd),
    /// and the `files` bucket is private anyway: the bare path is stored and
    /// signed at display time, while the display name lives in metadata.
    public func uploadFile(folderId: String, fileName: String, fileData: Data, fileType: String, fileSize: Int) async throws {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let storagePath = "\(folderId)/\(UUID().uuidString.lowercased()).\(ext.isEmpty ? "bin" : ext)"

        try await client.storage
            .from("files")
            .upload(storagePath, data: fileData, options: .init(contentType: fileType))

        let params: [String: Any?] = [
            "p_folder_id": folderId,
            "p_name": fileName,
            "p_file_url": storagePath,
            "p_file_type": fileType,
            "p_file_size": fileSize,
            "p_timespan": nil
        ]
        let _: AnyJSON = try await performRpc("upload_file_metadata", params: params as [String: Any])

        // Invalidate cached folder files
        let cacheKey = APICache.key("get_folder_files", params: ["p_folder_id": folderId])
        await cache.remove(cacheKey)
    }

    /// Copies a message attachment into a workspace folder: uploads the bytes to
    /// the `files` bucket under a fresh UUID path, then registers the metadata
    /// via `upload_file_metadata` — the same path the web's chat "Add to
    /// workspace" takes. Stores the bare storage path (resolved at display
    /// time, like the web) and keeps the original attachment name as the
    /// file's display name.
    public func addAttachmentToFolder(folderId: String, fileName: String, fileData: Data, fileType: String) async throws {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let storagePath = "\(folderId)/\(UUID().uuidString.lowercased()).\(ext.isEmpty ? "bin" : ext)"

        try await client.storage
            .from("files")
            .upload(storagePath, data: fileData, options: .init(contentType: fileType))

        let params: [String: Any?] = [
            "p_folder_id": folderId,
            "p_name": fileName,
            "p_file_url": storagePath,
            "p_file_type": fileType,
            "p_file_size": fileData.count,
            "p_timespan": nil
        ]
        let _: AnyJSON = try await performRpc("upload_file_metadata", params: params as [String: Any])

        // Invalidate cached folder files
        let cacheKey = APICache.key("get_folder_files", params: ["p_folder_id": folderId])
        await cache.remove(cacheKey)
    }


    /// Removes a track from the saved library (`unsave_track`).
    public func unsaveTrack(trackId: String) async throws {
        try await executeRpc("unsave_track", params: ["p_track_id": trackId])
        let cacheKey = APICache.key("get_user_library", params: nil)
        await cache.remove(cacheKey)
    }

    // MARK: - Track interactions (like / save)

    /// Whether the signed-in user has saved/liked a track (`get_track_interaction_status`).
    public func getTrackInteractionStatus(trackId: String) async throws -> ApiTrackInteractionStatus {
        return try await performRpc("get_track_interaction_status", params: ["p_track_id": trackId])
    }

    /// Likes a track (`like_track`).
    public func likeTrack(trackId: String) async throws {
        try await executeRpc("like_track", params: ["p_track_id": trackId])
        await cache.remove(APICache.key("get_user_likes", params: nil))
    }

    /// Unlikes a track (`unlike_track`).
    public func unlikeTrack(trackId: String) async throws {
        try await executeRpc("unlike_track", params: ["p_track_id": trackId])
        await cache.remove(APICache.key("get_user_likes", params: nil))
    }

    /// Saves a track to the library (`save_track`).
    public func saveTrack(trackId: String) async throws {
        try await executeRpc("save_track", params: ["p_track_id": trackId])
        await cache.remove(APICache.key("get_user_library", params: nil))
    }

    /// Deletes a file via Supabase RPC function
    public func deleteFile(fileId: String, folderId: String) async throws {
        // `delete_file` returns void — empty body, so it must not be decoded.
        try await executeRpc("delete_file", params: ["p_file_id": fileId])
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

    // MARK: - Track create v2 (web track-create parity)

    /// A buyer-download asset (MP3 / WAV / stems zip) for a paid tier.
    public struct TrackAssetUpload: Sendable {
        /// "mp3", "wav", or "stems".
        public let kind: String
        public let fileName: String
        public let data: Data

        public init(kind: String, fileName: String, data: Data) {
            self.kind = kind
            self.fileName = fileName
            self.data = data
        }
    }

    /// An enabled paid licensing tier (free is auto-created by a DB trigger).
    public struct TrackTierInput: Sendable {
        /// "creator", "pro", or "exclusive".
        public let tier: String
        public let price: Double

        public init(tier: String, price: Double) {
            self.tier = tier
            self.price = price
        }
    }

    public struct TrackCreditInput: Sendable {
        public let userId: String
        public let role: String

        public init(userId: String, role: String) {
            self.userId = userId
            self.role = role
        }
    }

    /// Creates a track via `create_track_v2`, mirroring the web's track-create
    /// submit flow: cover + streamable master go to `post-uploads`, paid
    /// downloadables go to the private `track-assets` bucket, and only bare
    /// storage paths are persisted.
    public func createTrackV2(
        userId: String,
        title: String,
        description: String?,
        genre: String,
        visibility: String,
        mediaData: Data,
        mediaFileName: String,
        isVideo: Bool,
        coverData: Data?,
        coverFileName: String?,
        credits: [TrackCreditInput],
        tags: [String],
        durationMs: Int?,
        paidTiers: [TrackTierInput],
        assets: [TrackAssetUpload],
        lookingForCollab: Bool
    ) async throws {
        let uid = userId.lowercased()

        var coverPath: String?
        if let coverData, let coverFileName {
            let path = "Visuals/\(uid)/\(UUID().uuidString)_cover.\(Self.safeStorageExt(coverFileName))"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg"))
            coverPath = path
        }

        // The streamable master — always lands in p_audio_url; videos live
        // under Visuals/ and flip p_has_visual.
        let folder = isVideo ? "Visuals" : "Posts"
        let mediaPath = "\(folder)/\(uid)/\(UUID().uuidString)_\(Self.safeStorageName(mediaFileName))"
        let mediaMime = isVideo ? "video/mp4" : Self.audioMimeType(forExt: Self.safeStorageExt(mediaFileName))
        try await client.storage
            .from("post-uploads")
            .upload(mediaPath, data: mediaData, options: .init(contentType: mediaMime))

        // Tier assets — private bucket, path starts with the uploader's id
        // to match the bucket's RLS policy.
        var assetPaths: [String: String] = [:]
        for asset in assets {
            let path = "\(uid)/\(UUID().uuidString)_\(asset.kind)_\(Self.safeStorageName(asset.fileName))"
            try await client.storage
                .from("track-assets")
                .upload(path, data: asset.data)
            assetPaths[asset.kind] = path
        }

        // Per-tier asset bundles — same kind mapping as the web form.
        func pickAssets(_ kinds: [String]) -> Any {
            let out = kinds.reduce(into: [String: String]()) { acc, kind in
                if let path = assetPaths[kind] { acc[kind] = path }
            }
            return out.isEmpty ? NSNull() : out
        }

        let tiersPayload: [[String: Any]] = paidTiers.map { tier in
            let kinds: [String] = switch tier.tier {
            case "creator": ["mp3", "wav"]
            case "pro": ["wav", "stems"]
            default: ["mp3", "wav", "stems"]
            }
            return [
                "tier": tier.tier,
                "price": tier.price,
                "currency": "USD",
                "available": true,
                "assets": pickAssets(kinds),
            ]
        }

        let params: [String: Any] = [
            "p_title": title,
            "p_audio_url": mediaPath,
            "p_cover_url": coverPath ?? NSNull(),
            "p_description": description ?? NSNull(),
            "p_visibility": visibility,
            "p_has_visual": isVideo,
            "p_genre": genre,
            "p_credits": credits.isEmpty
                ? NSNull()
                : credits.map { ["user_id": $0.userId, "role": $0.role] },
            "p_metadata": ["tags": tags],
            "p_duration_ms": durationMs ?? NSNull(),
            "p_tiers": tiersPayload,
            "p_looking_for_collab": lookingForCollab,
        ]
        try await executeRpc("create_track_v2", params: params)
        // The new track should appear on the author's profile immediately —
        // drop the cached profile (5-min TTL) so the next visit refetches.
        await invalidateProfile(userId: userId)
    }

    // MARK: - Track edit / delete (web track-edit parity)

    /// Author-only: quick visibility toggle (`update_track`; every other field is
    /// passed `NULL`, which the RPC coalesces to "keep the current value").
    public func updateTrackVisibility(trackId: String, visibility: String, userId: String) async throws {
        let params: [String: Any] = [
            "p_track_id": trackId,
            "p_title": NSNull(),
            "p_audio_url": NSNull(),
            "p_cover_url": NSNull(),
            "p_description": NSNull(),
            "p_visibility": visibility,
        ]
        try await executeRpc("update_track", params: params)
        await cache.remove(APICache.key("get_user_profile", params: ["profile_id": userId]))
        await cache.remove(APICache.key("get_track_metadata", params: ["p_track_id": trackId]))
    }

    /// Author-only: soft-deletes a track (`delete_track` flips `deprecated`;
    /// storage files aren't removed). Every read RPC filters `deprecated = false`.
    public func deleteTrack(trackId: String, userId: String) async throws {
        try await executeRpc("delete_track", params: ["p_track_id": trackId])
        await cache.remove(APICache.key("get_user_profile", params: ["profile_id": userId]))
    }

    /// Author-only: edits a track's metadata via `update_track` — mirrors the web's
    /// separate track-edit page (title/description/genre/visibility/tags/cover).
    /// Credits and licensing tiers aren't editable here (`create_track_v2`-only
    /// tables); the audio file itself can't be swapped either.
    ///
    /// `tags` is `nil` when the caller didn't change them — `p_metadata` is then
    /// omitted entirely so the RPC's coalesce leaves the whole metadata column
    /// (including any web-only keys) untouched, instead of stomping it with a
    /// `["tags": tags]` object that only knows about this one key.
    public func updateTrack(
        trackId: String,
        title: String,
        description: String?,
        genre: String,
        visibility: String,
        tags: [String]?,
        coverData: Data?,
        coverFileName: String?,
        userId: String
    ) async throws {
        var coverArg: Any = NSNull()
        if let coverData, let coverFileName {
            let path = "Visuals/\(userId.lowercased())/\(UUID().uuidString)_cover.\(Self.safeStorageExt(coverFileName))"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg"))
            coverArg = path
        }

        var params: [String: Any] = [
            "p_track_id": trackId,
            "p_title": title,
            "p_audio_url": NSNull(),
            "p_cover_url": coverArg,
            "p_description": description ?? NSNull(),
            "p_visibility": visibility,
            "p_genre": genre,
        ]
        if let tags {
            params["p_metadata"] = ["tags": tags]
        }

        try await executeRpc("update_track", params: params)
        await cache.remove(APICache.key("get_user_profile", params: ["profile_id": userId]))
        await cache.remove(APICache.key("get_track_metadata", params: ["p_track_id": trackId]))
    }

    // MARK: - Pack create (web pack-create parity)

    public struct PackFileUpload: Sendable {
        public let name: String
        public let data: Data
        public let isPreview: Bool

        public init(name: String, data: Data, isPreview: Bool) {
            self.name = name
            self.data = data
            self.isPreview = isPreview
        }
    }

    /// Creates a pack via `create_pack`: cover to `post-uploads/PackCovers/`,
    /// every file to the `packs` bucket (bare paths stored), then kicks the
    /// pack-zip edge function so the cached download is warm. Returns the pack id.
    public func createPack(
        userId: String,
        name: String,
        packType: String,
        description: String?,
        price: Double,
        formats: [String],
        gradient: String,
        tags: [String],
        isPublished: Bool,
        files: [PackFileUpload],
        coverData: Data?,
        coverFileName: String?
    ) async throws -> String {
        let uid = userId.lowercased()
        let packId = UUID().uuidString.lowercased()

        var coverPath: String?
        if let coverData, let coverFileName {
            let path = "PackCovers/\(uid)/\(packId).\(Self.safeStorageExt(coverFileName))"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg", upsert: true))
            coverPath = path
        }

        var fileRows: [[String: Any]] = []
        for file in files {
            let path = "\(packId)/\(UUID().uuidString)_\(Self.safeStorageName(file.name))"
            try await client.storage
                .from("packs")
                .upload(path, data: file.data)
            fileRows.append([
                "name": file.name,
                "category": NSNull(),
                "format": (file.name as NSString).pathExtension.uppercased(),
                "file_url": path,
                "file_size": file.data.count,
                "duration": NSNull(),
                "is_preview": file.isPreview,
            ])
        }

        let params: [String: Any] = [
            "p_pack_id": packId,
            "p_name": name,
            "p_pack_type": packType,
            "p_description": description ?? NSNull(),
            "p_price": price,
            "p_currency": "USD",
            "p_formats": formats,
            "p_gradient": gradient,
            "p_tags": tags,
            "p_is_published": isPublished,
            "p_files": fileRows,
            "p_cover_url": coverPath ?? NSNull(),
        ]
        try await executeRpc("create_pack", params: params)

        // Fire-and-forget zip warm-up — the download route has a fallback
        // if this fails or is still in flight (mirrors the web).
        Task { [client] in
            try? await client.functions.invoke(
                "pack-zip",
                options: .init(body: ["pack_id": packId])
            )
        }
        return packId
    }

    /// Full edit of a pack's metadata — mirrors the web's `update_pack` call
    /// (files aren't edited here). A new cover is uploaded; otherwise `p_cover_url`
    /// is null, which the RPC treats as "no change" (keeps the existing cover).
    public func updatePack(
        packId: String,
        name: String,
        packType: String,
        description: String?,
        price: Double,
        gradient: String,
        tags: [String],
        isPublished: Bool,
        coverData: Data?,
        coverFileName: String?,
        userId: String
    ) async throws {
        var coverArg: Any = NSNull()
        if let coverData, let coverFileName {
            let path = "PackCovers/\(userId.lowercased())/\(packId).\(Self.safeStorageExt(coverFileName))"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg", upsert: true))
            coverArg = path
        }
        let params: [String: Any] = [
            "p_pack_id": packId,
            "p_name": name,
            "p_pack_type": packType,
            "p_description": description ?? NSNull(),
            "p_price": price,
            "p_gradient": gradient,
            "p_tags": tags,
            "p_is_published": isPublished,
            "p_cover_url": coverArg,
        ]
        try await executeRpc("update_pack", params: params)
    }

    // MARK: - Service create (web service-create parity)

    public struct ServicePackageInput: Sendable {
        public let name: String
        public let price: Double
        public let delivery: Int
        public let revisions: Int
        public let features: [String]

        public init(name: String, price: Double, delivery: Int, revisions: Int, features: [String]) {
            self.name = name
            self.price = price
            self.delivery = delivery
            self.revisions = revisions
            self.features = features
        }
    }

    public struct ServiceProcessStepInput: Sendable {
        public let step: String
        public let description: String

        public init(step: String, description: String) {
            self.step = step
            self.description = description
        }
    }

    public struct ServiceFaqInput: Sendable {
        public let question: String
        public let answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    /// Creates a service via `create_service`, mirroring the web form: cover
    /// to `ServiceCovers/`, portfolio clips to `ServicePortfolios/` (both in
    /// `post-uploads`, bare paths stored), jsonb params passed as JSON text
    /// like the web's JSON.stringify.
    public func createService(
        userId: String,
        title: String,
        serviceType: String,
        price: Double,
        currency: String,
        deliveryTimeDays: Int?,
        longDescription: String?,
        revisions: Int,
        gradient: String,
        tags: [String],
        deliverables: [String],
        processSteps: [ServiceProcessStepInput],
        packages: [ServicePackageInput],
        portfolio: [ListingAttachmentUpload],
        faqs: [ServiceFaqInput],
        coverData: Data?,
        coverFileName: String?,
        isActive: Bool
    ) async throws {
        let uid = userId.lowercased()

        var coverPath: String?
        if let coverData, let coverFileName {
            let path = "ServiceCovers/\(uid)/\(UUID().uuidString).\(Self.safeStorageExt(coverFileName))"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg", upsert: true))
            coverPath = path
        }

        var portfolioRows: [[String: Any]] = []
        for clip in portfolio {
            let ext = Self.safeStorageExt(clip.fileName)
            let path = "ServicePortfolios/\(uid)/\(UUID().uuidString).\(ext)"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: clip.data, options: .init(contentType: Self.audioMimeType(forExt: ext), upsert: true))
            portfolioRows.append(["title": clip.title, "file_url": path])
        }

        let packagesJSON: [[String: Any]] = packages.map {
            [
                "name": $0.name,
                "price": $0.price,
                "delivery": $0.delivery,
                "revisions": $0.revisions,
                "features": $0.features,
            ]
        }
        let processJSON: [[String: Any]] = processSteps.map {
            ["step": $0.step, "description": $0.description]
        }
        let faqsJSON: [[String: Any]] = faqs.map {
            ["q": $0.question, "a": $0.answer]
        }

        let params: [String: Any] = [
            "p_title": title,
            "p_service_type": serviceType,
            "p_price": price,
            "p_currency": currency,
            "p_delivery_time_days": deliveryTimeDays ?? NSNull(),
            "p_long_description": longDescription ?? NSNull(),
            "p_revisions": revisions,
            "p_gradient": gradient,
            "p_tags": tags,
            "p_deliverables": Self.jsonText(deliverables),
            "p_process": Self.jsonText(processJSON),
            "p_packages": Self.jsonText(packagesJSON),
            "p_portfolio": Self.jsonText(portfolioRows),
            "p_faqs": Self.jsonText(faqsJSON),
            "p_license": NSNull(),
            "p_cover_url": coverPath ?? NSNull(),
            "p_is_active": isActive,
        ]
        try await executeRpc("create_service", params: params)
    }

    /// Full edit of a service — mirrors the web's `update_service` call. Portfolio
    /// clips kept as-is pass their existing path; new ones are uploaded. Cover and
    /// active state are left unchanged (the RPC treats null as "keep").
    public func updateService(
        serviceId: String,
        userId: String,
        title: String,
        serviceType: String,
        price: Double,
        currency: String,
        deliveryTimeDays: Int?,
        longDescription: String?,
        revisions: Int,
        gradient: String,
        tags: [String],
        deliverables: [String],
        processSteps: [ServiceProcessStepInput],
        packages: [ServicePackageInput],
        portfolio: [ListingAttachmentEdit],
        faqs: [ServiceFaqInput]
    ) async throws {
        let uid = userId.lowercased()
        var portfolioRows: [[String: Any]] = []
        for clip in portfolio {
            guard let data = clip.data, let fileName = clip.fileName else {
                if let existing = clip.existingFileUrl {
                    portfolioRows.append(["title": clip.title, "file_url": existing])
                }
                continue
            }
            let ext = Self.safeStorageExt(fileName)
            let path = "ServicePortfolios/\(uid)/\(UUID().uuidString).\(ext)"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: data, options: .init(contentType: Self.audioMimeType(forExt: ext), upsert: true))
            portfolioRows.append(["title": clip.title, "file_url": path])
        }

        let packagesJSON: [[String: Any]] = packages.map {
            ["name": $0.name, "price": $0.price, "delivery": $0.delivery, "revisions": $0.revisions, "features": $0.features]
        }
        let processJSON: [[String: Any]] = processSteps.map { ["step": $0.step, "description": $0.description] }
        let faqsJSON: [[String: Any]] = faqs.map { ["q": $0.question, "a": $0.answer] }

        let params: [String: Any] = [
            "p_service_id": serviceId,
            "p_title": title,
            "p_service_type": serviceType,
            "p_price": price,
            "p_currency": currency,
            "p_delivery_time_days": deliveryTimeDays ?? NSNull(),
            "p_long_description": longDescription ?? NSNull(),
            "p_revisions": revisions,
            "p_gradient": gradient,
            "p_tags": tags,
            "p_deliverables": Self.jsonText(deliverables),
            "p_process": Self.jsonText(processJSON),
            "p_packages": Self.jsonText(packagesJSON),
            "p_portfolio": Self.jsonText(portfolioRows),
            "p_faqs": Self.jsonText(faqsJSON),
            "p_license": NSNull(),
            "p_is_active": NSNull(),
        ]
        try await executeRpc("update_service", params: params)
    }

    /// JSON-encodes a JSONSerialization-compatible value to text, for jsonb
    /// params the web passes via JSON.stringify.
    private static func jsonText(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return "[]" }
        return string
    }

    /// Mirrors the web's `safeStorageExt`.
    private static func safeStorageExt(_ fileName: String) -> String {
        let raw = (fileName as NSString).pathExtension
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        return raw.isEmpty ? "bin" : String(raw.prefix(8))
    }

    /// Mirrors the web's filename sanitisation for storage paths.
    private static func safeStorageName(_ fileName: String) -> String {
        fileName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    /// An audio clip attached to a collab-board listing.
    public struct ListingAttachmentUpload: Sendable {
        public let title: String
        public let fileName: String
        public let data: Data

        public init(title: String, fileName: String, data: Data) {
            self.title = title
            self.fileName = fileName
            self.data = data
        }
    }

    /// Creates a collab-board listing. Mirrors the web's listing-create flow:
    /// each clip is uploaded to `post-uploads/ListingPortfolios/<user-id>/` and
    /// only the bare storage path is stored in the attachments jsonb.
    public func createListing(
        userId: String,
        category: String,
        title: String,
        description: String?,
        tags: [String],
        attachments: [ListingAttachmentUpload]
    ) async throws {
        var attachmentRows: [[String: String]] = []
        for clip in attachments {
            let rawExt = (clip.fileName as NSString).pathExtension
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            let ext = rawExt.isEmpty ? "bin" : String(rawExt.prefix(8))
            let path = "ListingPortfolios/\(userId.lowercased())/\(UUID().uuidString).\(ext)"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: clip.data, options: .init(contentType: Self.audioMimeType(forExt: ext), upsert: true))
            attachmentRows.append(["title": clip.title, "file_url": path])
        }

        // p_attachments is a jsonb *array* — pass the native array of
        // { title, file_url } objects so it serializes to a JSON array. Do NOT
        // pre-stringify it: that stored a jsonb *string* like "[]" instead of an
        // array, which then broke reads (`attachments.map is not a function`).
        let params: [String: Any] = [
            "p_category": category,
            "p_title": title,
            "p_description": description ?? NSNull(),
            "p_tags": tags,
            "p_attachments": attachmentRows,
        ]
        let _: AnyJSON = try await performRpc("create_listing", params: params)
    }

    /// A listing attachment for editing — either kept as-is (`existingFileUrl`) or
    /// a new file to upload (`data`).
    public struct ListingAttachmentEdit: Sendable {
        public let title: String
        public let existingFileUrl: String?
        public let data: Data?
        public let fileName: String?
        public init(title: String, existingFileUrl: String?, data: Data?, fileName: String?) {
            self.title = title
            self.existingFileUrl = existingFileUrl
            self.data = data
            self.fileName = fileName
        }
    }

    /// Full edit of a collab listing — mirrors the web's `update_listing` call
    /// (category/title/description/tags/attachments). New attachment files are
    /// uploaded; kept ones pass their existing path straight through.
    public func updateListing(
        listingId: String,
        userId: String,
        category: String,
        title: String,
        description: String?,
        tags: [String],
        attachments: [ListingAttachmentEdit]
    ) async throws {
        var attachmentRows: [[String: String]] = []
        for clip in attachments {
            // A newly-attached file (data) wins, so replacing a clip's audio takes;
            // otherwise keep the existing path.
            guard let data = clip.data, let fileName = clip.fileName else {
                if let existing = clip.existingFileUrl {
                    attachmentRows.append(["title": clip.title, "file_url": existing])
                }
                continue
            }
            let rawExt = (fileName as NSString).pathExtension
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            let ext = rawExt.isEmpty ? "bin" : String(rawExt.prefix(8))
            let path = "ListingPortfolios/\(userId.lowercased())/\(UUID().uuidString).\(ext)"
            try await client.storage
                .from("post-uploads")
                .upload(path, data: data, options: .init(contentType: Self.audioMimeType(forExt: ext), upsert: true))
            attachmentRows.append(["title": clip.title, "file_url": path])
        }

        let params: [String: Any] = [
            "p_listing_id": listingId,
            "p_category": category,
            "p_title": title,
            "p_description": description ?? NSNull(),
            "p_tags": tags,
            "p_attachments": attachmentRows,
        ]
        let _: AnyJSON = try await performRpc("update_listing", params: params)
    }

    private static func audioMimeType(forExt ext: String) -> String {
        switch ext {
        case "wav", "wave": "audio/wav"
        case "m4a", "mp4": "audio/mp4"
        case "aif", "aiff": "audio/aiff"
        case "flac": "audio/flac"
        case "ogg": "audio/ogg"
        default: "audio/mpeg"
        }
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

    /// True when the username is free to claim (signup wizard).
    public func checkUsernameAvailable(_ username: String) async throws -> Bool {
        try await performRpc("check_username_available", params: ["p_username": username])
    }

    /// Creates the user's profile row after auth (signup wizard) — mirrors
    /// the web register flow's `create_user` call.
    public func createUser(
        username: String,
        accountType: String = "collaborator",
        bio: String?,
        location: String?,
        profileImageUrl: String?,
        bannerImageUrl: String?,
        tags: [String]?
    ) async throws {
        let params: [String: Any] = [
            "p_username": username,
            "p_account_type": accountType,
            "p_bio": bio ?? NSNull(),
            "p_location": location ?? NSNull(),
            "p_profile_image_url": profileImageUrl ?? NSNull(),
            "p_banner_image_url": bannerImageUrl ?? NSNull(),
            "p_tags": tags ?? NSNull(),
        ]
        try await executeRpc("create_user", params: params)
    }

    /// Updates the current user's profile via Supabase RPC function
    public func updateUserProfile(userId: String, username: String?, bio: String?, accountType: String?, location: String?, profileImageUrl: String?, bannerImageUrl: String?, tags: [String]?) async throws -> ApiUpdateProfileResponse {
        // Mirrors the web app's `update_user` RPC. NB: every column except
        // account_type is written exactly as passed (no COALESCE), so callers
        // must send the *current* value of any field they don't want cleared.
        let params: [String: Any] = [
            "p_username": username ?? NSNull(),
            "p_bio": bio ?? NSNull(),
            "p_account_type": accountType ?? NSNull(),
            "p_location": location ?? NSNull(),
            "p_profile_image_url": profileImageUrl ?? NSNull(),
            "p_banner_image_url": bannerImageUrl ?? NSNull(),
            "p_tags": tags.map { $0 as Any } ?? NSNull()
        ]
        let result: ApiUpdateProfileResponse = try await performRpc("update_user", params: params)

        // Invalidate cached profile so next load fetches fresh data
        let cacheKey = APICache.key("get_user_profile", params: ["profile_id": userId])
        await cache.remove(cacheKey)

        return result
    }

    /// Uploads a user avatar to Supabase Storage and returns the public URL
    /// (version-stamped — see `versioned`).
    public func uploadAvatar(userId: String, imageData: Data) async throws -> URL {
        let storagePath = "\(userId).png"

        try await client.storage
            .from("user-avatars")
            .upload(storagePath, data: imageData, options: .init(contentType: "image/png", upsert: true))

        let publicURL = try client.storage
            .from("user-avatars")
            .getPublicURL(path: storagePath)

        return Self.versioned(publicURL)
    }

    /// Uploads a user banner to Supabase Storage and returns the public URL
    /// (version-stamped — see `versioned`).
    public func uploadBanner(userId: String, imageData: Data) async throws -> URL {
        let storagePath = "\(userId).png"

        try await client.storage
            .from("user-banners")
            .upload(storagePath, data: imageData, options: .init(contentType: "image/png", upsert: true))

        let publicURL = try client.storage
            .from("user-banners")
            .getPublicURL(path: storagePath)

        return Self.versioned(publicURL)
    }

    /// Appends `?v=<timestamp>` to an upserted object's public URL. The storage
    /// path is FIXED per user, so without this the stored URL never changes and
    /// every image cache (Kingfisher, the storage CDN, browsers) keeps serving
    /// the old picture after an update.
    private static func versioned(_ url: URL) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))]
        return comps?.url ?? url
    }

    /// Fetches track detail from Supabase RPC function (cached 5 min)
    public func getTrackMetadata(trackId: String) async throws -> ApiTrackDetail {
        return try await cachedRpc("get_track_metadata", params: ["p_track_id": trackId], ttl: 300)
    }

    /// Fetches comments for a track from Supabase RPC function (cached 1 min)
    public func getTrackComments(trackId: String) async throws -> [ApiTrackComment] {
        return try await cachedRpc("get_track_comments", params: ["p_track_id": trackId], ttl: 60)
    }

    /// Fetches the track's license tiers straight from `track_licenses` (the web
    /// reads the same table). Display only — checkout lives on the web.
    public func getTrackLicenses(trackId: String) async throws -> [ApiTrackLicense] {
        try await client
            .from("track_licenses")
            .select("id, track_id, license_type, price, currency, terms, available")
            .eq("track_id", value: trackId)
            .execute()
            .value
    }

    /// Posts a comment on a track via Supabase RPC function
    public func postComment(content: String, trackId: String, parentId: String? = nil, timestampSeconds: Double? = nil, timestampEndSeconds: Double? = nil) async throws {
        let params: [String: Any?] = [
            "p_content": content,
            "p_track_id": trackId,
            "p_parent_id": parentId, // explicitly NULL when not replying
            // The RPC params are `integer` — send whole seconds, not a Double
            // (a JSON float like `8.0` fails the cast to integer).
            "p_timestamp_seconds": timestampSeconds.map { Int($0) },
            "p_timestamp_end_seconds": timestampEndSeconds.map { Int($0) }
        ]
        let _: AnyJSON = try await performRpc("post_comment", params: params as [String: Any])
        // Invalidate cached comments for this track
        let cacheKey = APICache.key("get_track_comments", params: ["p_track_id": trackId])
        await cache.remove(cacheKey)
    }

    /// Deletes a comment (own comments only — enforced server-side). `delete_comment`
    /// returns void, so use `executeRpc` (decoding an empty body would throw).
    public func deleteComment(commentId: String, trackId: String) async throws {
        let params: [String: Any?] = ["p_comment_id": commentId]
        try await executeRpc("delete_comment", params: params as [String: Any])
        let cacheKey = APICache.key("get_track_comments", params: ["p_track_id": trackId])
        await cache.remove(cacheKey)
    }

    // MARK: - File comments (workspace files) — mirrors track comments.

    public func getFileComments(fileId: String) async throws -> [ApiTrackComment] {
        return try await cachedRpc("get_file_comments", params: ["p_file_id": fileId], ttl: 60)
    }

    public func postFileComment(content: String, fileId: String, parentId: String? = nil, timestampSeconds: Double? = nil, timestampEndSeconds: Double? = nil) async throws {
        let params: [String: Any?] = [
            "p_file_id": fileId,
            "p_content": content,
            "p_parent_id": parentId,
            // Integer params — send whole seconds, not a Double (see postComment).
            "p_timestamp_seconds": timestampSeconds.map { Int($0) },
            "p_timestamp_end_seconds": timestampEndSeconds.map { Int($0) }
        ]
        let _: AnyJSON = try await performRpc("add_file_comment", params: params as [String: Any])
        await cache.remove(APICache.key("get_file_comments", params: ["p_file_id": fileId]))
    }

    public func deleteFileComment(commentId: String, fileId: String) async throws {
        try await executeRpc("delete_file_comment", params: ["p_comment_id": commentId])
        await cache.remove(APICache.key("get_file_comments", params: ["p_file_id": fileId]))
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

    /// Executes an RPC whose result we don't need. `void`-returning Postgres
    /// functions reply with an empty body, and decoding `AnyJSON` from empty data
    /// throws — so these calls must run the request without decoding the response.
    private func executeRpc(_ functionName: String, params: [String: Any]? = nil) async throws {
        do {
            if let params = params {
                let jsonData = try JSONSerialization.data(withJSONObject: params)
                let anyJSON = try JSONDecoder().decode(AnyJSON.self, from: jsonData)
                _ = try await client.rpc(functionName, params: anyJSON).execute()
            } else {
                _ = try await client.rpc(functionName).execute()
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

/// Used for both liked tracks (`get_user_likes`) and the saved library
/// (`get_user_library`) — their shapes overlap; fields absent in one decode to nil.
public struct ApiUserLike: Codable, Sendable, Identifiable {
    public var id: String { trackId }
    public let trackId: String
    public let title: String
    public let coverUrl: String?
    public let audioUrl: String?
    public let streams: Int?
    public let createdAt: String?
    public let savedAt: String?
    public let genre: String?
    public let durationMs: Int?
    public let artist: ApiLikeArtist?

    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case title
        case coverUrl = "cover_url"
        case audioUrl = "audio_url"
        case streams
        case createdAt = "created_at"
        case savedAt = "saved_at"
        case genre
        case durationMs = "duration_ms"
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
    public let credits: [ApiTrackCredit]?
    public let metadata: ApiTrackMetadata?
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

/// A collaborator credited on a track. `get_track_metadata` returns these as a
/// JSON array (one per `track_credits` row), or null when there are none.
public struct ApiTrackCredit: Codable, Sendable, Identifiable {
    public let userId: String?
    public let username: String?
    public let profileImageUrl: String?
    public let accountType: String?
    public let role: String?

    public var id: String { "\(userId ?? "")|\(role ?? "")" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
        case accountType = "account_type"
        case role
    }
}

/// Free-form track metadata (`tracks.metadata` jsonb). Only `tags` is modeled;
/// any other keys are ignored.
public struct ApiTrackMetadata: Codable, Sendable {
    public let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case tags
    }
}

// MARK: - Track Comments DTOs

public struct ApiCommentUser: Codable, Sendable {
    public let userId: String
    public let username: String?
    public let profileImageUrl: String?

    public init(userId: String, username: String?, profileImageUrl: String?) {
        self.userId = userId
        self.username = username
        self.profileImageUrl = profileImageUrl
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case profileImageUrl = "profile_image_url"
    }
}

/// A purchasable license tier for a track (free / creator / pro / exclusive).
public struct ApiTrackLicense: Codable, Sendable, Identifiable {
    public let id: String
    public let trackId: String
    public let licenseType: String
    public let price: Double
    public let currency: String?
    public let terms: String?
    public let available: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case trackId = "track_id"
        case licenseType = "license_type"
        case price, currency, terms, available
    }
}

public struct ApiTrackComment: Codable, Sendable, Identifiable {
    public var id: String { commentId }
    public let commentId: String
    public let content: String
    public let createdAt: String
    /// nil for file comments (which carry `file_id` instead).
    public let trackId: String?
    public let parentId: String?
    public let user: ApiCommentUser
    public var replies: [ApiTrackComment]?
    /// Playback position (seconds) this comment is pinned to, if any.
    public let timestampSeconds: Double?
    /// Optional end of a timestamped range.
    public let timestampEndSeconds: Double?

    public init(commentId: String, content: String, createdAt: String, trackId: String?, parentId: String?, user: ApiCommentUser, replies: [ApiTrackComment]?, timestampSeconds: Double? = nil, timestampEndSeconds: Double? = nil) {
        self.commentId = commentId
        self.content = content
        self.createdAt = createdAt
        self.trackId = trackId
        self.parentId = parentId
        self.user = user
        self.replies = replies
        self.timestampSeconds = timestampSeconds
        self.timestampEndSeconds = timestampEndSeconds
    }

    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case content
        case createdAt = "created_at"
        case trackId = "track_id"
        case parentId = "parent_id"
        case user
        case replies
        case timestampSeconds = "timestamp_seconds"
        case timestampEndSeconds = "timestamp_end_seconds"
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
