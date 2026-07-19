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
}

// MARK: - Shared Supabase Client

public let supabaseClient = SupabaseClient(
    supabaseURL: URL(string: SupabaseConfig.baseURL)!,
    supabaseKey: SupabaseConfig.apiKey
)

// MARK: - Supabase Service Implementation

public final class SupabaseService: Sendable {
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
        return try await cachedRpc("get_home_tracks", params: nil, ttl: CacheTTL.long)
    }

    /// Tracks from artists the current user follows (Explore "Following" tab).
    public func getFollowingFeed() async throws -> [ApiHomeTrack] {
        return try await cachedRpc("get_following_feed", params: ["p_limit": 30, "p_offset": 0], ttl: CacheTTL.short)
    }

    /// General track feed (Explore "Tracks" tab). `seed` shuffles the ordering
    /// server-side — mirror the web by passing a fresh random seed per session
    /// so the recommendations vary instead of returning the same order forever.
    /// Cached per-seed, so the same seed reuses results but a new seed refetches.
    public func getExploreTracksFeed(seed: Int) async throws -> [ApiHomeTrack] {
        return try await cachedRpc("get_home_feed", params: ["p_seed": seed, "p_limit": 30, "p_offset": 0], ttl: CacheTTL.medium)
    }

    /// Artists to explore (Explore "Artists" tab).
    public func getExploreArtists() async throws -> [ApiExploreArtist] {
        return try await cachedRpc("get_explore_artists", params: ["p_limit": 30, "p_offset": 0], ttl: CacheTTL.medium)
    }

    /// Drops the cached home-surface responses (rails, following, artists,
    /// folders) so a pull-to-refresh refetches fresh data instead of serving
    /// the TTL cache. The explore feed re-rolls its seed (new cache key) and
    /// listings/workspace activity are uncached, so they need no entry here.
    public func invalidateHomeCaches() async {
        await cache.removeAll(matching: "rpc:get_home_tracks")
        await cache.removeAll(matching: "rpc:get_following_feed")
        await cache.removeAll(matching: "rpc:get_explore_artists")
        await cache.removeAll(matching: "rpc:get_user_folders")
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
            .from(.messageAttachments)
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
        return try await cachedRpc("get_user_profile", params: ["profile_id": userId], ttl: CacheTTL.long)
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
        return try await cachedRpc("get_tracks_credited_to_user", params: ["p_user_id": userId], ttl: CacheTTL.medium)
    }

    /// Fetches the sample/preset/plugin packs owned by `userId` ("Packs" tab). Cached 2 min.
    public func getUserPacks(userId: String) async throws -> [ApiUserPack] {
        return try await cachedRpc("get_user_packs", params: ["p_user_id": userId], ttl: CacheTTL.medium)
    }

    /// Fetches the current user's liked tracks (cached 1 min)
    public func getUserLikes() async throws -> [ApiUserLike] {
        return try await cachedRpc("get_user_likes", params: nil, ttl: CacheTTL.short)
    }

    /// Fetches the user's saved library (`user_saves`), matching the web app's "Saved" tab.
    public func getUserLibrary() async throws -> [ApiUserLike] {
        return try await cachedRpc("get_user_library", params: nil, ttl: CacheTTL.short)
    }

    /// Fetches the current user's notifications (cached 30s)
    public func getUserNotifications() async throws -> [ApiNotification] {
        return try await cachedRpc("get_user_notifications", params: nil, ttl: CacheTTL.realtime)
    }

    /// Marks all of the signed-in user's notifications as read.
    public func markNotificationsRead() async throws {
        // Void-returning RPC — empty body, must not be decoded.
        try await executeRpc("mark_notifications_read", params: nil)
    }

    /// Fetches the signed-in user's notification toggles (cached 1 min).
    public func getNotificationPreferences() async throws -> ApiNotificationPreferences {
        return try await cachedRpc("get_notification_preferences", params: nil, ttl: CacheTTL.short)
    }

    /// Fetches per-track analytics for the signed-in creator (cached 2 min).
    public func getMyTrackAnalytics() async throws -> [ApiTrackAnalytics] {
        return try await cachedRpc("get_my_track_analytics", params: nil, ttl: CacheTTL.medium)
    }

    /// Creator engagement aggregates — followers / likes / saves / comments
    /// (totals + last-30-day deltas) and 30-day shares (`get_my_engagement_stats`).
    public func getMyEngagementStats() async throws -> ApiEngagementStats {
        return try await cachedRpc("get_my_engagement_stats", params: nil, ttl: CacheTTL.medium)
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
        return try await cachedRpc("get_user_folders", params: nil, ttl: CacheTTL.short)
    }

    /// Collaborators' actions from the past month (uploads / comments / joins)
    /// across the caller's workspace folders (`get_workspace_activity`, newest
    /// first; excludes the caller's own actions). Uncached — it's "what's new".
    public func getWorkspaceActivity(limit: Int = 30) async throws -> [ApiWorkspaceActivity] {
        return try await performRpc("get_workspace_activity", params: ["p_limit": limit])
    }

    /// Marketplace browse data — public packs + services (`get_explore_data`).
    public func getExploreData() async throws -> ApiExploreData {
        return try await cachedRpc("get_explore_data", params: nil, ttl: CacheTTL.short)
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
            .from(.postUploads)
            .upload(path, data: imageData, options: .init(contentType: "image/jpeg"))
        return try client.storage
            .from(.postUploads)
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
        return try await cachedRpc("get_folder_files", params: ["p_folder_id": folderId], ttl: CacheTTL.short)
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
        try await executeRpc("toggle_user_follow", params: ["target_user": targetUser])
        // Invalidate cached profile for this user
        let cacheKey = APICache.key("get_user_profile", params: ["profile_id": targetUser])
        await cache.remove(cacheKey)
    }

    // MARK: - Reporting & blocking (UGC safety, App Store 1.2)

    /// Files a content or user report (`submit_report`). The DB auto-hides the
    /// target on severe categories or once enough distinct reports arrive.
    public func submitReport(
        targetType: ReportTargetType,
        targetId: String,
        reason: ReportReason,
        details: String? = nil
    ) async throws {
        let trimmed = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await executeRpc("submit_report", params: [
            "p_target_type": targetType.rawValue,
            "p_target_id": targetId,
            "p_reason": reason.rawValue,
            "p_details": (trimmed?.isEmpty == false ? trimmed! : NSNull()) as Any,
        ])
    }

    /// Blocks a user (`block_user`): hides both parties' content from each other
    /// and severs follows + collaborator ties. Clears the cache and posts
    /// `.userBlockStateChanged` so live screens refetch their filtered reads.
    public func blockUser(_ userId: String) async throws {
        try await executeRpc("block_user", params: ["p_blocked_id": userId])
        await cache.clear()
        NotificationCenter.default.post(name: .userBlockStateChanged, object: nil)
    }

    /// Unblocks a user (`unblock_user`).
    public func unblockUser(_ userId: String) async throws {
        try await executeRpc("unblock_user", params: ["p_blocked_id": userId])
        await cache.clear()
        NotificationCenter.default.post(name: .userBlockStateChanged, object: nil)
    }

    /// Users the current account has blocked (`get_blocked_users`).
    public func getBlockedUsers() async throws -> [ApiBlockedUser] {
        return try await performRpc("get_blocked_users")
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
            debugLog("[SupabaseService] send_collab_request ERROR: \(error)")
            throw SupabaseError.serverError("\(error)")
        }
        // The viewer's collaborator status changed — drop the cached profile.
        await cache.remove(APICache.key("get_user_profile", params: ["profile_id": targetId]))
    }

    /// Live collaborator status with another user — 'none' / 'pending' /
    /// 'accepted'. The thread's request card keeps reading "accepted" as
    /// history after a removal, so anything needing the CURRENT state (e.g.
    /// the conversation's Remove Collaborator option) asks this instead.
    public func getCollabStatus(otherUserId: String) async throws -> String {
        return try await performRpc("get_collab_status", params: ["p_other_id": otherUserId])
    }

    /// Ends an accepted collaboration (`remove_collaborator`) — the RPC deletes
    /// the relationship (both directions covered) and archives the pair's DM
    /// for the caller, so the thread moves to their inbox's Archived section
    /// with history intact.
    public func removeCollaborator(userId: String) async throws {
        try await executeRpc("remove_collaborator", params: ["p_target_id": userId])
        // The viewer's collaborator status changed — drop the cached profile.
        await cache.remove(APICache.key("get_user_profile", params: ["profile_id": userId]))
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

    /// Renames/updates a folder (`update_folder`). Owner-only; `description` is
    /// overwritten, so pass the current value to preserve it.
    public func updateFolder(folderId: String, name: String, description: String?) async throws {
        var params: [String: Any] = ["p_folder_id": folderId, "p_name": name]
        if let description { params["p_description"] = description }
        try await executeRpc("update_folder", params: params)
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
        try await executeRpc("add_folder_member", params: [
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
            .from(.files)
            .upload(storagePath, data: fileData, options: .init(contentType: fileType))

        let params: [String: Any?] = [
            "p_folder_id": folderId,
            "p_name": fileName,
            "p_file_url": storagePath,
            "p_file_type": fileType,
            "p_file_size": fileSize,
            "p_timespan": nil
        ]
        try await executeRpc("upload_file_metadata", params: params as [String: Any])

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
            .from(.files)
            .upload(storagePath, data: fileData, options: .init(contentType: fileType))

        let params: [String: Any?] = [
            "p_folder_id": folderId,
            "p_name": fileName,
            "p_file_url": storagePath,
            "p_file_type": fileType,
            "p_file_size": fileData.count,
            "p_timespan": nil
        ]
        try await executeRpc("upload_file_metadata", params: params as [String: Any])

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
    @discardableResult
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
    ) async throws -> String {
        let uid = userId.lowercased()

        var coverPath: String?
        if let coverData, let coverFileName {
            let path = "Visuals/\(uid)/\(UUID().uuidString)_cover.\(Self.safeStorageExt(coverFileName))"
            try await client.storage
                .from(.postUploads)
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg"))
            coverPath = path
        }

        // The streamable master — always lands in p_audio_url; videos live
        // under Visuals/ and flip p_has_visual.
        let folder = isVideo ? "Visuals" : "Posts"
        let mediaPath = "\(folder)/\(uid)/\(UUID().uuidString)_\(Self.safeStorageName(mediaFileName))"
        let mediaMime = isVideo ? "video/mp4" : Self.audioMimeType(forExt: Self.safeStorageExt(mediaFileName))
        try await client.storage
            .from(.postUploads)
            .upload(mediaPath, data: mediaData, options: .init(contentType: mediaMime))

        // Tier assets — private bucket, path starts with the uploader's id
        // to match the bucket's RLS policy.
        var assetPaths: [String: String] = [:]
        for asset in assets {
            let path = "\(uid)/\(UUID().uuidString)_\(asset.kind)_\(Self.safeStorageName(asset.fileName))"
            try await client.storage
                .from(.trackAssets)
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
        // The RPC returns the new track's id — callers use it to open the
        // freshly-posted track (expanded player).
        struct Created: Decodable {
            let trackId: String
            enum CodingKeys: String, CodingKey { case trackId = "track_id" }
        }
        let created: Created = try await performRpc("create_track_v2", params: params)
        // The new track should appear on the author's profile immediately —
        // drop the cached profile (5-min TTL) so the next visit refetches.
        await invalidateProfile(userId: userId)
        return created.trackId
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
                .from(.postUploads)
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
                .from(.postUploads)
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg", upsert: true))
            coverPath = path
        }

        var fileRows: [[String: Any]] = []
        for file in files {
            // uid-prefixed so the `packs_insert_authenticated` storage policy can pin
            // writes to the caller's own path (foldername[1] = auth.uid()); without the
            // prefix any authed user could write anywhere in the public-read bucket.
            let path = "\(uid)/\(packId)/\(UUID().uuidString)_\(Self.safeStorageName(file.name))"
            try await client.storage
                .from(.packs)
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
                .from(.postUploads)
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
                .from(.postUploads)
                .upload(path, data: coverData, options: .init(contentType: "image/jpeg", upsert: true))
            coverPath = path
        }

        var portfolioRows: [[String: Any]] = []
        for clip in portfolio {
            let ext = Self.safeStorageExt(clip.fileName)
            let path = "ServicePortfolios/\(uid)/\(UUID().uuidString).\(ext)"
            try await client.storage
                .from(.postUploads)
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
                .from(.postUploads)
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
    @discardableResult
    public func createListing(
        userId: String,
        category: String,
        title: String,
        description: String?,
        tags: [String],
        attachments: [ListingAttachmentUpload]
    ) async throws -> String {
        var attachmentRows: [[String: String]] = []
        for clip in attachments {
            let rawExt = (clip.fileName as NSString).pathExtension
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            let ext = rawExt.isEmpty ? "bin" : String(rawExt.prefix(8))
            let path = "ListingPortfolios/\(userId.lowercased())/\(UUID().uuidString).\(ext)"
            try await client.storage
                .from(.postUploads)
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
        // The RPC returns `{ success, listing_id }` — callers use the id to
        // open the freshly-posted listing's detail page.
        struct Created: Decodable {
            let listingId: String
            enum CodingKeys: String, CodingKey { case listingId = "listing_id" }
        }
        let created: Created = try await performRpc("create_listing", params: params)
        return created.listingId
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
                .from(.postUploads)
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
        try await executeRpc("update_listing", params: params)
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
            .from(.userAvatars)
            .upload(storagePath, data: imageData, options: .init(contentType: "image/png", upsert: true))

        let publicURL = try client.storage
            .from(.userAvatars)
            .getPublicURL(path: storagePath)

        return Self.versioned(publicURL)
    }

    /// Uploads a user banner to Supabase Storage and returns the public URL
    /// (version-stamped — see `versioned`).
    public func uploadBanner(userId: String, imageData: Data) async throws -> URL {
        let storagePath = "\(userId).png"

        try await client.storage
            .from(.userBanners)
            .upload(storagePath, data: imageData, options: .init(contentType: "image/png", upsert: true))

        let publicURL = try client.storage
            .from(.userBanners)
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
        return try await cachedRpc("get_track_metadata", params: ["p_track_id": trackId], ttl: CacheTTL.long)
    }

    /// Fetches comments for a track from Supabase RPC function (cached 1 min)
    public func getTrackComments(trackId: String) async throws -> [ApiTrackComment] {
        return try await cachedRpc("get_track_comments", params: ["p_track_id": trackId], ttl: CacheTTL.short)
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
        try await executeRpc("post_comment", params: params as [String: Any])
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
        return try await cachedRpc("get_file_comments", params: ["p_file_id": fileId], ttl: CacheTTL.short)
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
        try await executeRpc("add_file_comment", params: params as [String: Any])
        await cache.remove(APICache.key("get_file_comments", params: ["p_file_id": fileId]))
    }

    public func deleteFileComment(commentId: String, fileId: String) async throws {
        try await executeRpc("delete_file_comment", params: ["p_comment_id": commentId])
        await cache.remove(APICache.key("get_file_comments", params: ["p_file_id": fileId]))
    }

    /// Generic RPC call with caching
    public func cachedRpc<T: Decodable & Encodable & Sendable>(
        _ functionName: String,
        params: [String: Any]? = nil,
        ttl: TimeInterval = APICache.defaultTTL
    ) async throws -> T {
        let cacheKey = APICache.key(functionName, params: params)

        // Return cached (decoded) value if fresh.
        if let cached: T = await cache.get(cacheKey) {
            debugLog("[SupabaseService] rpc(\(functionName)) CACHE HIT")
            return cached
        }

        // Serialize params up front (Sendable) so the fetch closure can cross into the
        // cache actor; concurrent misses for this key then share one round-trip.
        let paramsData = try params.map { try JSONSerialization.data(withJSONObject: $0) }
        let data = try await cache.coalescedData(cacheKey, ttl: ttl) { [self] in
            try await performRpcData(functionName, paramsData: paramsData)
        }
        let value: T
        do { value = try JSONDecoder().decode(T.self, from: data) }
        catch {
            // Log decode failures — a 200 whose body doesn't match the DTO would
            // otherwise be SILENT (performRpcData already logged the 200 status), which
            // hides "loaded fine but UI still shimmers" bugs.
            debugLog("[SupabaseService] rpc(\(functionName)) DECODE ERROR: \(error)")
            throw mapError(error)
        }
        await cache.storeDecoded(cacheKey, value)
        return value
    }

    // MARK: - Private

    private func performRpc<T: Decodable>(_ functionName: String, params: [String: Any]? = nil) async throws -> T {
        do {
            if let params = params {
                let jsonData = try JSONSerialization.data(withJSONObject: params)
                let anyJSON = try JSONDecoder().decode(AnyJSON.self, from: jsonData)

                let response = try await client.rpc(functionName, params: anyJSON)
                    .execute()
                debugLog("[SupabaseService] rpc(\(functionName)) status: \(response.status), bytes: \(response.data.count)")
                return try JSONDecoder().decode(T.self, from: response.data)
            } else {
                let response = try await client.rpc(functionName)
                    .execute()
                debugLog("[SupabaseService] rpc(\(functionName)) status: \(response.status), bytes: \(response.data.count)")
                return try JSONDecoder().decode(T.self, from: response.data)
            }
        } catch {
            debugLog("[SupabaseService] rpc(\(functionName)) ERROR: \(error)")
            throw mapError(error)
        }
    }

    /// Runs an RPC and returns the raw response body WITHOUT decoding — the coalesced
    /// cache path (`cachedRpc` → `APICache.coalescedData`) decodes once afterward, so
    /// concurrent misses for a key share one network round-trip.
    private func performRpcData(_ functionName: String, paramsData: Data?) async throws -> Data {
        do {
            if let paramsData {
                let anyJSON = try JSONDecoder().decode(AnyJSON.self, from: paramsData)
                let response = try await client.rpc(functionName, params: anyJSON).execute()
                debugLog("[SupabaseService] rpc(\(functionName)) status: \(response.status), bytes: \(response.data.count)")
                return response.data
            } else {
                let response = try await client.rpc(functionName).execute()
                debugLog("[SupabaseService] rpc(\(functionName)) status: \(response.status), bytes: \(response.data.count)")
                return response.data
            }
        } catch {
            debugLog("[SupabaseService] rpc(\(functionName)) ERROR: \(error)")
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
            debugLog("[SupabaseService] rpc(\(functionName)) ERROR: \(error)")
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
    
    /// User-facing copy. Deliberately generic/actionable — the raw server text
    /// (Postgres / PostgREST / constraint detail) is NEVER surfaced here; it's
    /// available via `rawDetail` for logging + programmatic matching only.
    public var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return Self.friendly(rawDetail: message)
        case .unauthorized:
            return "Please sign in and try again."
        case .notFound:
            return "That content is no longer available."
        case .invalidURL, .invalidResponse, .clientError, .decodingError, .unknown:
            return "Something went wrong. Please try again."
        }
    }

    /// The raw server/system detail — for logging and for code that matches specific
    /// error signatures. Never show this to users (see `errorDescription`).
    public var rawDetail: String {
        switch self {
        case .serverError(let m): return m
        case .decodingError(let e): return e.localizedDescription
        case .invalidURL: return "invalidURL"
        case .invalidResponse: return "invalidResponse"
        case .unauthorized: return "unauthorized"
        case .notFound: return "notFound"
        case .clientError(let c): return "clientError \(c)"
        case .unknown(let c): return "unknown \(c)"
        }
    }

    /// Maps a raw server error string to safe, human copy. Known, user-actionable
    /// signatures get specific messages; everything else falls back to a generic line
    /// so Postgres / constraint internals never reach the UI. Raw text stays in
    /// `debugLog` (logged at the call site before mapping).
    static func friendly(rawDetail raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("network error") || s.contains("offline") || s.contains("connection")
            || s.contains("timed out") || s.contains("could not connect") || s.contains("internet") {
            return "Can't reach Volspire. Check your connection and try again."
        }
        if s.contains("rate limit") || s.contains("too many") || s.contains("rate_limited") || s.contains("once every") {
            return "You're doing that a bit too fast — give it a moment and try again."
        }
        if s.contains("not_authenticated") || s.contains("auth required") || s.contains("jwt") {
            return "Please sign in and try again."
        }
        if s.contains("account_suspended") || s.contains("suspended") {
            return "Your account is suspended. Contact support if you think this is a mistake."
        }
        if s.contains("user_unavailable") || s.contains("blocked") {
            return "You can't do that with this user."
        }
        if s.contains("not_authorized") || s.contains("not_a_member") || s.contains("forbidden") || s.contains("permission") {
            return "You don't have permission to do that."
        }
        if s.contains("unsupported_file_type") {
            return "That file type isn't supported."
        }
        if s.contains("too_long") || s.contains("too long") || s.contains("value too long")
            || s.contains("_length") || s.contains("check constraint") {
            return "That's too long — please shorten it and try again."
        }
        if s.contains("duplicate") || s.contains("already exists") || s.contains("unique constraint") {
            return "That already exists."
        }
        if s.contains("not found") || s.contains("no rows") {
            return "That content is no longer available."
        }
        return "Something went wrong. Please try again."
    }
}

public extension Error {
    /// Raw server detail when this is a `SupabaseError` (for matching specific error
    /// signatures); otherwise the system description. Never display this to users —
    /// use `localizedDescription`, which is friendly for `SupabaseError`.
    var serverRawDetail: String {
        (self as? SupabaseError)?.rawDetail ?? localizedDescription
    }
}
