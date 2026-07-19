//
//  APIModels.swift
//  Services
//
//  DTOs decoded from the Supabase RPC / PostgREST responses. Extracted from
//  SupabaseService.swift, which retains the client, service protocol, and
//  implementation.
//

import Foundation

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
    /// MIME type of the last message's attachment (e.g. "image/jpeg"), for a
    /// type-aware preview ("Image" vs "Attachment"). Nil for plain messages.
    public let lastMessageAttachmentType: String?
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
        case lastMessageAttachmentType = "last_message_attachment_type"
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
    /// Blocked (either direction) or suspended — show "User unavailable"
    /// instead of the profile.
    public let isUnavailable: Bool?
    /// The viewer blocked this user — drives the Unblock affordance on the
    /// unavailable state.
    public let viewerHasBlocked: Bool?

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
        case isUnavailable = "is_unavailable"
        case viewerHasBlocked = "viewer_has_blocked"
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
