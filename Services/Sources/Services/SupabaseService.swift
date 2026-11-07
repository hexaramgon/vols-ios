//
//  SupabaseService.swift
//  Services
//
//  Created by GitHub Copilot on 01.02.2026.
//

import Foundation
import SharedUtilities
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

/// What a valid session's auth user actually owns, per `get_account_status`.
///
/// Signing in is not the same as having an account: Supabase mints an
/// `auth.users` row the first time someone taps "Continue with Google", while
/// the `public.users` row is only ever written by the wizard's `create_user`.
public enum AccountStatus: String, Sendable {
    /// A live profile row — the only state that may open the app.
    case active
    /// Tombstoned by `anonymize_self` (deleted from another device/the web).
    case deleted
    /// Auth user with no profile row: onboarding was never finished.
    case missing = "none"
}

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

    /// Drops the cached home-surface responses (rails, following, artists,
    /// folders) so a pull-to-refresh refetches fresh data instead of serving
    /// the TTL cache. The explore feed re-rolls its seed (new cache key) and
    /// listings/workspace activity are uncached, so they need no entry here.
    public func invalidateHomeCaches() async {
        await cache.removeAll(matching: "rpc:get_home_tracks")
        await cache.removeAll(matching: "rpc:get_following_feed")
        await cache.removeAll(matching: "rpc:get_collab_tracks")
        await cache.removeAll(matching: "rpc:get_explore_artists")
        await cache.removeAll(matching: "rpc:get_user_folders")
    }

    /// Drops every cached pack response — the marketplace list
    /// (`get_explore_data`), pack details and profile pack lists — so a pack
    /// create / edit shows everywhere at once, and Marketplace pull-to-refresh
    /// really refetches.
    public func invalidatePackCaches() async {
        await cache.removeAll(matching: "rpc:get_explore_data")
        await cache.removeAll(matching: "rpc:get_pack")
        await cache.removeAll(matching: "rpc:get_user_packs")
    }

    /// Drops the cached library response so a user-initiated refresh refetches
    /// fresh data inside the TTL window (mutations already invalidate this key
    /// themselves; playlist mutations invalidate via `invalidatePlaylists`).
    public func invalidateLibraryCaches() async {
        await cache.removeAll(matching: "rpc:get_user_library")
    }

    /// Drops one folder's cached file rows (mutating RPCs do this themselves;
    /// this is for user-initiated refreshes).
    public func invalidateFolderFilesCache(folderId: String) async {
        await cache.remove(APICache.key("get_folder_files", params: ["p_folder_id": folderId]))
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
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return try await uploadToStorage(
            .messageAttachments,
            path: "\(convoId)/\(userId)/\(stamp)-\(UUID().uuidString).\(Self.safeStorageExt(fileName))",
            data: data,
            contentType: fileType
        )
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
        await cache.remove(APICache.key("get_user_listings", params: ["p_user_id": userId]))
        await cache.remove(APICache.key("get_tracks_credited_to_user", params: ["p_user_id": userId]))
        await cache.remove(APICache.key("get_user_packs", params: ["p_user_id": userId]))
        await cache.remove(APICache.key("get_user_listings", params: ["p_user_id": userId]))
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
        // Drop the cached (now-stale, is_read=false) feed so reopening the page
        // within the realtime TTL re-fetches the read state instead of showing
        // the rows unread again.
        await cache.remove(APICache.key("get_user_notifications", params: nil))
    }

    /// Fetches the signed-in user's notification toggles (cached 1 min).
    public func getNotificationPreferences() async throws -> ApiNotificationPreferences {
        return try await cachedRpc("get_notification_preferences", params: nil, ttl: CacheTTL.short)
    }

    /// Fetches per-track analytics for the signed-in creator (cached 2 min).
    public func getMyTrackAnalytics() async throws -> [ApiTrackAnalytics] {
        return try await cachedRpc("get_my_track_analytics", params: nil, ttl: CacheTTL.medium)
    }

    /// Drops the cached analytics so a pull-to-refresh refetches.
    public func invalidateAnalytics() async {
        await cache.removeAll(matching: "rpc:get_my_track_analytics")
    }

    /// Creator engagement aggregates — followers / likes / saves / comments
    /// (totals + last-30-day deltas) and 30-day shares (`get_my_engagement_stats`).
    public func getMyEngagementStats() async throws -> ApiEngagementStats {
        return try await cachedRpc("get_my_engagement_stats", params: nil, ttl: CacheTTL.medium)
    }

    /// In-app unread indicator counts (`get_unread_counts` — the same RPC the
    /// web uses for its dots). Coalesced with a 5s window: launch and
    /// tab-switch clusters used to fire 3-4 duplicate badge fetches within a
    /// second. `force` bypasses the window — required after a mark-read, where
    /// a pre-mark cached count would strand the dot.
    public func getUnreadCounts(force: Bool = false) async throws -> ApiUnreadCounts {
        let key = APICache.key("get_unread_counts")
        if force { await cache.remove(key) }
        return try await cachedRpc("get_unread_counts", ttl: 5)
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

    /// The cheapest paid, available license per sellable track — the
    /// Marketplace tab's "Beats for sale" (`get_for_sale_track_prices`; track
    /// details come from `getTracksByIds`).
    public func getForSaleTrackPrices(limit: Int = 300) async throws -> [ApiTrackPrice] {
        try await performRpc("get_for_sale_track_prices", params: ["p_limit": limit])
    }

    /// The collab board, hottest first (`get_listings_feed`: engagement +
    /// recency, see its migration). Pass the previous page's last
    /// `ApiListing.cursor` for the next page; empty `categories` = all.
    public func getListingsFeed(categories: Set<String>, limit: Int = 20, cursor: String?) async throws -> [ApiListing] {
        try await performRpc("get_listings_feed", params: [
            "p_categories": categories.isEmpty ? NSNull() : Array(categories).sorted(),
            "p_limit": limit,
            "p_cursor": cursor ?? NSNull(),
        ])
    }

    /// Counts a view of a listing (`record_listing_view`: one per viewer per
    /// day; the author's own views don't count). Feeds the board ranking.
    public func recordListingView(listingId: String) async throws {
        try await executeRpc("record_listing_view", params: ["p_listing_id": listingId])
    }

    /// The signed-in user's saved collab listings (`get_saved_listings`),
    /// newest-saved first. Same `ApiListing` shape as `get_listings`.
    public func getSavedListings() async throws -> [ApiListing] {
        return try await performRpc("get_saved_listings")
    }

    /// A specific user's collab-board listings (`get_user_listings`) — same shape as
    /// the board feed. Includes the owner's non-open listings when they're viewing.
    public func getUserListings(userId: String) async throws -> [ApiListing] {
        return try await cachedRpc("get_user_listings", params: ["p_user_id": userId], ttl: CacheTTL.medium)
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

    public func postListingComment(listingId: String, content: String, parentId: String? = nil) async throws -> ApiListingComment {
        // Always send p_parent_id (NULL for a top-level comment): omitting it makes
        // the call ambiguous between the two `post_listing_comment` overloads.
        let params: [String: Any] = [
            "p_listing_id": listingId,
            "p_content": content,
            "p_parent_id": parentId ?? NSNull()
        ]
        return try await performRpc("post_listing_comment", params: params)
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
        await invalidateUserListings()
    }

    /// Author-only: permanently delete a listing (`delete_listing`).
    public func deleteListing(listingId: String) async throws {
        try await executeRpc("delete_listing", params: ["p_listing_id": listingId])
        await invalidateUserListings()
    }

    /// Drops every cached `get_user_listings` page (the profile Listings tab)
    /// after a create/edit/status change/delete, so it doesn't serve a stale list.
    public func invalidateUserListings() async {
        await cache.removeAll(matching: "rpc:get_user_listings")
    }

    /// Full detail for a marketplace sound pack (`get_pack`).
    public func getPack(packId: String) async throws -> ApiPackDetail {
        return try await cachedRpc("get_pack", params: ["p_pack_id": packId], ttl: CacheTTL.medium)
    }

    /// A short-lived (10 min) download link to a FREE pack's zip. The
    /// `pack-zip` edge function checks access via `get_pack`, builds + caches
    /// the zip if needed, and returns `url` for free packs only — paid packs
    /// never get one here.
    public func freePackDownloadURL(packId: String) async throws -> URL {
        struct Response: Decodable { let url: String? }
        do {
            let response: Response = try await client.functions.invoke(
                "pack-zip",
                options: .init(body: ["pack_id": packId])
            )
            guard let raw = response.url, let url = URL(string: raw) else { throw SupabaseError.notFound }
            return url
        } catch let error as SupabaseError {
            throw error
        } catch {
            throw mapError(error)
        }
    }

    /// Counts a pack download (`increment_pack_downloads`).
    public func recordPackDownload(packId: String) async throws {
        try await executeRpc("increment_pack_downloads", params: ["p_pack_id": packId])
    }

    /// Full detail for a marketplace service (`get_service_detail`).
    public func getServiceDetail(serviceId: String) async throws -> ApiServiceDetail {
        return try await cachedRpc("get_service_detail", params: ["p_service_id": serviceId], ttl: CacheTTL.medium)
    }

    // MARK: - Reviews (packs + services — `reviews` table, same as the web)

    /// `target_type` for the review RPCs.
    public enum ReviewTarget: String, Sendable {
        case pack, service
    }

    /// Whether the caller may review this item, and whether they already did.
    public func reviewEligibility(targetId: String, target: ReviewTarget) async throws -> ApiReviewEligibility {
        try await performRpc("can_review", params: ["p_target_id": targetId, "p_target_type": target.rawValue])
    }

    /// Posts a 1–5 star review with optional text (`create_review`; one per
    /// person per item — the table's unique key rejects a second).
    public func createReview(targetId: String, target: ReviewTarget, rating: Int, body: String) async throws {
        try await executeRpc("create_review", params: [
            "p_target_id": targetId,
            "p_target_type": target.rawValue,
            "p_rating": rating,
            "p_body": body,
        ])
        await invalidateReviewCaches()
    }

    /// The owner's performance numbers for a pack (`get_pack_stats`; uncached
    /// — it's "how is it doing right now").
    public func getPackStats(packId: String) async throws -> ApiPackStats {
        try await performRpc("get_pack_stats", params: ["p_pack_id": packId])
    }

    /// The author's performance numbers for a collab listing
    /// (`get_listing_stats`; uncached).
    public func getListingStats(listingId: String) async throws -> ApiListingStats {
        try await performRpc("get_listing_stats", params: ["p_listing_id": listingId])
    }

    /// Deletes one of the caller's own reviews (`delete_review`).
    public func deleteReview(reviewId: String) async throws {
        try await executeRpc("delete_review", params: ["p_review_id": reviewId])
        await invalidateReviewCaches()
    }

    /// Reviews ride inside the cached pack / service detail (and the average
    /// rating on the Marketplace cards), so drop those after a change.
    private func invalidateReviewCaches() async {
        await invalidatePackCaches()
        await cache.removeAll(matching: "rpc:get_service_detail")
    }

    // MARK: - Releases (grouped releases on a profile — RPC-only)

    /// A profile's releases, newest first (`get_user_releases`).
    public func getUserReleases(userId: String) async throws -> [ApiRelease] {
        return try await performRpc("get_user_releases", params: ["p_user_id": userId])
    }

    /// A release with its ordered tracks (`get_release`).
    public func getRelease(releaseId: String) async throws -> ApiReleaseDetail {
        return try await performRpc("get_release", params: ["p_release_id": releaseId])
    }

    /// The caller's releases + whether each holds `trackId` (`get_releases_for_track`).
    public func getReleasesForTrack(trackId: String) async throws -> [ApiReleaseMembership] {
        return try await performRpc("get_releases_for_track", params: ["p_track_id": trackId])
    }

    /// Creates a release (`create_release`) and returns its id. `releaseDate`
    /// is "yyyy-MM-dd"; `trackIds` (the caller's own tracks) land in order.
    public func createRelease(
        title: String,
        description: String? = nil,
        visibility: String = "public",
        releaseDate: String? = nil,
        trackIds: [String] = []
    ) async throws -> String {
        let params: [String: Any] = [
            "p_title": title,
            "p_description": (description?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? NSNull(),
            "p_visibility": visibility,
            "p_release_date": releaseDate ?? NSNull(),
            "p_track_ids": trackIds,
        ]
        let created: CreatedRelease = try await performRpc("create_release", params: params)
        return created.releaseId
    }

    private struct CreatedRelease: Decodable {
        let releaseId: String
    }

    /// Updates a release (`update_release`). nil leaves a field; an empty
    /// description clears it; `clearReleaseDate` removes the date.
    public func updateRelease(
        releaseId: String,
        title: String? = nil,
        description: String? = nil,
        visibility: String? = nil,
        coverUrl: String? = nil,
        releaseDate: String? = nil,
        clearReleaseDate: Bool = false
    ) async throws {
        var params: [String: Any] = ["p_release_id": releaseId, "p_clear_release_date": clearReleaseDate]
        if let title { params["p_title"] = title }
        if let description { params["p_description"] = description }
        if let visibility { params["p_visibility"] = visibility }
        if let coverUrl { params["p_cover_url"] = coverUrl }
        if let releaseDate { params["p_release_date"] = releaseDate }
        try await executeRpc("update_release", params: params)
    }

    /// Deletes a release (`delete_release`) — its tracks are untouched.
    public func deleteRelease(releaseId: String) async throws {
        try await executeRpc("delete_release", params: ["p_release_id": releaseId])
    }

    /// Appends the caller's tracks to a release (`add_tracks_to_release`).
    public func addTracksToRelease(releaseId: String, trackIds: [String]) async throws {
        try await executeRpc("add_tracks_to_release", params: ["p_release_id": releaseId, "p_track_ids": trackIds])
    }

    /// Removes a track from a release (`remove_track_from_release`).
    public func removeTrackFromRelease(releaseId: String, trackId: String) async throws {
        try await executeRpc("remove_track_from_release", params: ["p_release_id": releaseId, "p_track_id": trackId])
    }

    /// Sets a release's track order (`reorder_release`).
    public func reorderRelease(releaseId: String, trackIds: [String]) async throws {
        try await executeRpc("reorder_release", params: ["p_release_id": releaseId, "p_track_ids": trackIds])
    }

    /// Uploads a release cover to `post-uploads` and returns its storage path
    /// (bare, like the other covers the RPCs store). Second path segment is the
    /// uploader's auth id (storage RLS); the stamp busts image caches.
    public func uploadReleaseCover(releaseId: String, userId: String, imageData: Data) async throws -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        return try await uploadToStorage(
            .postUploads,
            path: "Releases/\(userId.lowercased())/\(releaseId)-\(stamp).jpg",
            data: imageData,
            contentType: "image/jpeg"
        )
    }

    // MARK: - Playlists

    /// The signed-in user's playlists (`get_user_playlists`).
    /// Cached 1 min — the Add-to-Playlist sheet refetched it on every open.
    /// Mutations invalidate via `invalidatePlaylists`.
    public func getUserPlaylists() async throws -> [ApiPlaylist] {
        return try await cachedRpc("get_user_playlists", ttl: CacheTTL.short)
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
        await invalidatePlaylists()
        return created.playlistId
    }

    private struct CreatedPlaylist: Decodable {
        let playlistId: String
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
        await invalidatePlaylists()
    }

    /// Uploads a playlist cover to the public `post-uploads` bucket and returns its public URL.
    /// Path's second segment must be the uploader's auth id (storage RLS); a timestamp keeps
    /// each save's URL unique so caches refetch the new image.
    public func uploadPlaylistCover(playlistId: String, userId: String, imageData: Data) async throws -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let path = try await uploadToStorage(
            .postUploads,
            path: "Playlists/\(userId.lowercased())/\(playlistId)-\(stamp).jpg",
            data: imageData,
            contentType: "image/jpeg"
        )
        return try client.storage
            .from(.postUploads)
            .getPublicURL(path: path)
            .absoluteString
    }

    /// Deletes a playlist (`delete_playlist`).
    public func deletePlaylist(playlistId: String) async throws {
        try await executeRpc("delete_playlist", params: ["p_playlist_id": playlistId])
        await invalidatePlaylists()
    }

    /// Adds a track to a playlist (`add_track_to_playlist`).
    public func addTrackToPlaylist(playlistId: String, trackId: String) async throws {
        try await executeRpc("add_track_to_playlist", params: ["p_playlist_id": playlistId, "p_track_id": trackId])
        await invalidatePlaylists(trackId: trackId)
    }

    /// Removes a track from a playlist (`remove_track_from_playlist`).
    public func removeTrackFromPlaylist(playlistId: String, trackId: String) async throws {
        try await executeRpc("remove_track_from_playlist", params: ["p_playlist_id": playlistId, "p_track_id": trackId])
        await invalidatePlaylists(trackId: trackId)
    }

    /// Ids of the caller's playlists that already contain the given track
    /// (`get_playlists_for_track`) — used to pre-check the "Add to playlist" rows.
    public func getPlaylistsForTrack(trackId: String) async throws -> [String] {
        return try await cachedRpc("get_playlists_for_track", params: ["p_track_id": trackId], ttl: CacheTTL.short)
    }

    /// Drops the playlist caches — call after any playlist mutation.
    public func invalidatePlaylists(trackId: String? = nil) async {
        await cache.remove(APICache.key("get_user_playlists"))
        if let trackId {
            await cache.remove(APICache.key("get_playlists_for_track", params: ["p_track_id": trackId]))
        } else {
            // A create/rename/delete can change any track's membership list.
            await cache.removeAll(matching: "rpc:get_playlists_for_track")
        }
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

    /// The viewer's saved packs, newest-saved first (`get_saved_packs`).
    public func getSavedPacks() async throws -> [ApiMarketplacePack] {
        try await performRpc("get_saved_packs")
    }

    public func savePack(packId: String) async throws {
        try await executeRpc("save_pack", params: ["p_pack_id": packId])
    }

    public func unsavePack(packId: String) async throws {
        try await executeRpc("unsave_pack", params: ["p_pack_id": packId])
    }

    // MARK: Folder share links (owner only)

    /// The folder's active public link, nil when it has none.
    public func getFolderShareLink(folderId: String) async throws -> ApiFolderShareLink? {
        try await performRpc("get_folder_share_link", params: ["p_folder_id": folderId])
    }

    /// Creates the folder's public link — or a fresh one, revoking the old.
    public func createFolderShareLink(folderId: String, allowDownloads: Bool, expiresInDays: Int?) async throws -> ApiFolderShareLink {
        try await performRpc("create_folder_share_link", params: [
            "p_folder_id": folderId,
            "p_allow_downloads": allowDownloads,
            "p_expires_in_days": expiresInDays ?? NSNull(),
        ])
    }

    /// Changes the active link's options (nil = unchanged; `clearExpiry` =
    /// never expires; `expiresInDays` counts from now).
    public func updateFolderShareLink(folderId: String, allowDownloads: Bool? = nil, expiresInDays: Int? = nil,
                                      clearExpiry: Bool = false) async throws -> ApiFolderShareLink {
        try await performRpc("update_folder_share_link", params: [
            "p_folder_id": folderId,
            "p_allow_downloads": allowDownloads ?? NSNull(),
            "p_expires_in_days": expiresInDays ?? NSNull(),
            "p_clear_expiry": clearExpiry,
        ])
    }

    /// Turns the folder's public link off (it stops working immediately).
    public func revokeFolderShareLink(folderId: String) async throws {
        try await executeRpc("revoke_folder_share_link", params: ["p_folder_id": folderId])
    }

    /// Links a free pack into a folder (`add_pack_to_folder`; idempotent).
    public func addPackToFolder(packId: String, folderId: String) async throws {
        try await executeRpc("add_pack_to_folder", params: ["p_folder_id": folderId, "p_pack_id": packId])
    }

    /// Unlinks a pack from a folder (`remove_pack_from_folder`).
    public func removePackFromFolder(packId: String, folderId: String) async throws {
        try await executeRpc("remove_pack_from_folder", params: ["p_folder_id": folderId, "p_pack_id": packId])
    }

    /// The packs linked into a folder, newest first (`get_folder_packs`).
    public func getFolderPacks(folderId: String) async throws -> [ApiFolderPack] {
        try await performRpc("get_folder_packs", params: ["p_folder_id": folderId])
    }

    /// Ids of the folders the caller can access that already contain the track
    /// (`get_folders_for_track`) — used to pre-check the "Add to Workspace" rows.
    public func getFoldersForTrack(trackId: String) async throws -> [String] {
        return try await performRpc("get_folders_for_track", params: ["p_track_id": trackId])
    }

    /// Toggles follow/unfollow for a user
    public func toggleFollow(targetUser: String) async throws {
        try await executeRpc("toggle_user_follow", params: ["target_user": targetUser])
        await invalidateProfile(userId: targetUser)
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

    /// The caller's followers, newest first (`get_my_followers`), each with
    /// whether the caller follows them back.
    public func getMyFollowers(limit: Int = 200, offset: Int = 0) async throws -> [ApiFollower] {
        return try await performRpc("get_my_followers", params: ["p_limit": limit, "p_offset": offset])
    }

    /// Users the current account has blocked (`get_blocked_users`).
    public func getBlockedUsers() async throws -> [ApiUserSummary] {
        return try await performRpc("get_blocked_users")
    }

    /// Sends a collaboration request to an artist (`send_collab_request`), optionally
    /// attaching up to 3 of the sender's tracks. The DB raises `collab_rate_limited`
    /// (one request per artist per week) and `collab_attachment_cap` — surfaced via
    /// the thrown error's text so callers can show a friendly message. Returns the
    /// pair's DM convo id (the RPC finds or creates it).
    @discardableResult
    public func sendCollabRequest(targetId: String, message: String, trackIds: [String]? = nil) async throws -> String {
        let params: [String: Any] = [
            "p_target_id": targetId,
            "p_message": message,
            "p_track_ids": (trackIds?.isEmpty == false ? trackIds! : NSNull()) as Any
        ]
        // mapError keeps the raw error text (PostgrestError includes its
        // `message`), so the caller can detect guards like `collab_rate_limited`.
        let convoId: String = try await performRpc("send_collab_request", params: params)
        // The viewer's collaborator status changed — drop the cached profile.
        await invalidateProfile(userId: targetId)
        return convoId.lowercased()
    }

    /// Live collaborator status with another user — 'none' / 'pending' /
    /// 'accepted'. The thread's request card keeps reading "accepted" as
    /// history after a removal, so anything needing the CURRENT state (e.g.
    /// the conversation's Remove Collaborator option) asks this instead.
    public func getCollabStatus(otherUserId: String) async throws -> String {
        return try await performRpc("get_collab_status", params: ["p_other_id": otherUserId])
    }

    /// The collab listing a conversation was opened from — nil for plain DMs
    /// or when the listing was deleted (`get_convo_listing_id`, participant-scoped).
    public func getConvoListingId(convoId: String) async throws -> String? {
        return try await performRpc("get_convo_listing_id", params: ["p_convo_id": convoId])
    }

    /// Ends an accepted collaboration (`remove_collaborator`) — the RPC deletes
    /// the relationship (both directions covered) and archives the pair's DM
    /// for the caller, so the thread moves to their inbox's Archived section
    /// with history intact.
    public func removeCollaborator(userId: String) async throws {
        try await executeRpc("remove_collaborator", params: ["p_target_id": userId])
        // The viewer's collaborator status changed — drop the cached profile.
        await invalidateProfile(userId: userId)
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
    public func searchUsers(query: String, limit: Int = 8) async throws -> [ApiUserSummary] {
        try await performRpc("search_users", params: ["p_query": query, "p_limit": limit])
    }

    /// Your collaborators — people you've worked with — for the folder member
    /// picker (mirrors the web's `get_my_collaborators`, used by the share-folder modal).
    public func getMyCollaborators() async throws -> [ApiUserSummary] {
        try await performRpc("get_my_collaborators")
    }

    /// Full-catalog search (`search_all`) — tracks, artists, packs, services.
    /// Matches the web app's `/api/search` (which calls the same RPC, limit 20).
    public func searchAll(query: String, limit: Int = 20) async throws -> ApiSearchResults {
        try await performRpc("search_all", params: ["p_query": query, "p_limit": limit])
    }

    /// Uploads a file into a workspace folder then saves metadata via RPC —
    /// used both for direct uploads and for copying a message attachment into a
    /// folder (the same path the web's chat "Add to workspace" takes).
    /// The storage key is a fresh UUID, same scheme as the web: raw display
    /// names made invalid or colliding storage keys (spaces/brackets/$;
    /// re-uploading a name 409'd), and the `files` bucket is private anyway —
    /// the bare path is stored and signed at display time, while the display
    /// name lives in metadata.
    public func uploadFile(folderId: String, fileName: String, fileData: Data, fileType: String) async throws {
        let storagePath = try await uploadToStorage(
            .files,
            path: "\(folderId)/\(UUID().uuidString.lowercased()).\(Self.safeStorageExt(fileName))",
            data: fileData,
            contentType: fileType
        )

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
    /// submit flow: the cover goes to `post-uploads`, the streamable master to
    /// the private `track-media` bucket (`<uid>/…` — the tracks row's
    /// constraint requires the owner's folder), paid downloadables to the
    /// private `track-assets` bucket, and only bare storage paths are persisted.
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
        // Reject mislabeled / streaming-format media before anything uploads
        // (see MediaSniffer — the web runs the same check).
        try MediaSniffer.validate(mediaData, fileName: mediaFileName)

        let uid = userId.lowercased()

        let coverPath = try await uploadCoverIfPicked(coverData, fileName: coverFileName) {
            "Visuals/\(uid)/\(UUID().uuidString)_cover.\($0)"
        }

        // The streamable master (audio, or the video for a visual track —
        // p_has_visual flips) — always lands in p_audio_url.
        let mediaPath = try await uploadToStorage(
            .trackMedia,
            path: "\(uid)/\(UUID().uuidString)_\(Self.safeStorageName(mediaFileName))",
            data: mediaData,
            contentType: isVideo ? "video/mp4" : Self.audioMimeType(forExt: Self.safeStorageExt(mediaFileName))
        )

        // Tier assets — private bucket, path starts with the uploader's id
        // to match the bucket's RLS policy.
        var assetPaths: [String: String] = [:]
        for asset in assets {
            assetPaths[asset.kind] = try await uploadToStorage(
                .trackAssets,
                path: "\(uid)/\(UUID().uuidString)_\(asset.kind)_\(Self.safeStorageName(asset.fileName))",
                data: asset.data
            )
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
        await invalidateProfile(userId: userId)
        await cache.remove(APICache.key("get_track_metadata", params: ["p_track_id": trackId]))
        // Title/cover/visibility feed the home rails — refetches must be fresh.
        await invalidateHomeCaches()
    }

    /// Author-only: soft-deletes a track (`delete_track` flips `deprecated`;
    /// storage files aren't removed). Every read RPC filters `deprecated = false`.
    public func deleteTrack(trackId: String, userId: String) async throws {
        try await executeRpc("delete_track", params: ["p_track_id": trackId])
        await invalidateProfile(userId: userId)
        // The rails/feeds caches may still contain the dead row — drop them so
        // a refresh inside the TTL can't resurrect it after stores patched it out.
        await invalidateHomeCaches()
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
        let coverPath = try await uploadCoverIfPicked(coverData, fileName: coverFileName) {
            "Visuals/\(userId.lowercased())/\(UUID().uuidString)_cover.\($0)"
        }

        var params: [String: Any] = [
            "p_track_id": trackId,
            "p_title": title,
            "p_audio_url": NSNull(),
            "p_cover_url": coverPath ?? NSNull(),
            "p_description": description ?? NSNull(),
            "p_visibility": visibility,
            "p_genre": genre,
        ]
        if let tags {
            params["p_metadata"] = ["tags": tags]
        }

        try await executeRpc("update_track", params: params)
        await invalidateProfile(userId: userId)
        await cache.remove(APICache.key("get_track_metadata", params: ["p_track_id": trackId]))
        // Title/cover/visibility feed the home rails — refetches must be fresh.
        await invalidateHomeCaches()
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
        tags: [String],
        isPublished: Bool,
        files: [PackFileUpload],
        coverData: Data?,
        coverFileName: String?
    ) async throws -> String {
        let uid = userId.lowercased()
        let packId = UUID().uuidString.lowercased()

        let coverPath = try await uploadCoverIfPicked(coverData, fileName: coverFileName, upsert: true) {
            "PackCovers/\(uid)/\(packId).\($0)"
        }

        var fileRows: [[String: Any]] = []
        for file in files {
            // uid-prefixed so the `packs_insert_authenticated` storage policy can pin
            // writes to the caller's own path (foldername[1] = auth.uid()); without the
            // prefix any authed user could write anywhere in the public-read bucket.
            let path = try await uploadToStorage(
                .packs,
                path: "\(uid)/\(packId)/\(UUID().uuidString)_\(Self.safeStorageName(file.name))",
                data: file.data
            )
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
            "p_tags": tags,
            "p_is_published": isPublished,
            "p_files": fileRows,
            "p_cover_url": coverPath ?? NSNull(),
        ]
        try await executeRpc("create_pack", params: params)
        await invalidatePackCaches()

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
        tags: [String],
        isPublished: Bool,
        coverData: Data?,
        coverFileName: String?,
        userId: String
    ) async throws {
        let coverPath = try await uploadCoverIfPicked(coverData, fileName: coverFileName, upsert: true) {
            "PackCovers/\(userId.lowercased())/\(packId).\($0)"
        }
        let params: [String: Any] = [
            "p_pack_id": packId,
            "p_name": name,
            "p_pack_type": packType,
            "p_description": description ?? NSNull(),
            "p_price": price,
            "p_tags": tags,
            "p_is_published": isPublished,
            "p_cover_url": coverPath ?? NSNull(),
        ]
        try await executeRpc("update_pack", params: params)
        await invalidatePackCaches()
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

        let coverPath = try await uploadCoverIfPicked(coverData, fileName: coverFileName, upsert: true) {
            "ServiceCovers/\(uid)/\(UUID().uuidString).\($0)"
        }

        let portfolioRows = try await uploadClipRows(portfolio, folder: "ServicePortfolios", userId: userId)

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
        let portfolioRows = try await uploadClipRows(portfolio, folder: "ServicePortfolios", userId: userId)

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

    // MARK: - Storage upload helpers

    /// The one storage-upload call: uploads bytes and returns the bare storage
    /// path (paths are resolved to URLs at display time via StorageService).
    @discardableResult
    private func uploadToStorage(
        _ bucket: StorageBucket,
        path: String,
        data: Data,
        contentType: String? = nil,
        upsert: Bool = false
    ) async throws -> String {
        // Every upload funnels through here — refuse over-cap files with a
        // clear message instead of the server's generic rejection.
        guard data.count <= bucket.maxUploadBytes else {
            throw SupabaseError.fileTooLarge(maxBytes: bucket.maxUploadBytes)
        }
        try await client.storage
            .from(bucket)
            .upload(path, data: data, options: .init(contentType: contentType, upsert: upsert))
        return path
    }

    /// Shared cover-image upload (covers are JPEG re-encodes from the picker).
    /// Returns the bare path, or nil when no cover was picked. `path` receives
    /// the sanitised extension and builds the bucket path.
    private func uploadCoverIfPicked(
        _ data: Data?,
        fileName: String?,
        upsert: Bool = false,
        path: (_ ext: String) -> String
    ) async throws -> String? {
        guard let data, let fileName else { return nil }
        return try await uploadToStorage(
            .postUploads,
            path: path(Self.safeStorageExt(fileName)),
            data: data,
            contentType: "image/jpeg",
            upsert: upsert
        )
    }

    /// The shared `{ title, file_url }` row builder for listing attachments and
    /// service portfolios: uploads new clips to `<folder>/<uid>/<uuid>.<ext>`
    /// and passes kept ones' existing paths straight through.
    private func uploadClipRows(
        _ clips: [ListingAttachmentEdit],
        folder: String,
        userId: String
    ) async throws -> [[String: String]] {
        var rows: [[String: String]] = []
        for clip in clips {
            // A newly-attached file (data) wins, so replacing a clip's audio takes;
            // otherwise keep the existing path.
            guard let data = clip.data, let fileName = clip.fileName else {
                if let existing = clip.existingFileUrl {
                    rows.append(["title": clip.title, "file_url": existing])
                }
                continue
            }
            let ext = Self.safeStorageExt(fileName)
            let path = try await uploadToStorage(
                .postUploads,
                path: "\(folder)/\(userId.lowercased())/\(UUID().uuidString).\(ext)",
                data: data,
                contentType: Self.audioMimeType(forExt: ext),
                upsert: true
            )
            rows.append(["title": clip.title, "file_url": path])
        }
        return rows
    }

    private func uploadClipRows(
        _ clips: [ListingAttachmentUpload],
        folder: String,
        userId: String
    ) async throws -> [[String: String]] {
        try await uploadClipRows(
            clips.map { ListingAttachmentEdit(title: $0.title, existingFileUrl: nil, data: $0.data, fileName: $0.fileName) },
            folder: folder,
            userId: userId
        )
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
        let attachmentRows = try await uploadClipRows(attachments, folder: "ListingPortfolios", userId: userId)

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
        }
        let created: Created = try await performRpc("create_listing", params: params)
        await invalidateUserListings()
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
        let attachmentRows = try await uploadClipRows(attachments, folder: "ListingPortfolios", userId: userId)

        let params: [String: Any] = [
            "p_listing_id": listingId,
            "p_category": category,
            "p_title": title,
            "p_description": description ?? NSNull(),
            "p_tags": tags,
            "p_attachments": attachmentRows,
        ]
        try await executeRpc("update_listing", params: params)
        await invalidateUserListings()
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

    /// Which account state the signed-in session is in — the gate `AuthManager`
    /// opens the app with.
    ///
    /// Not `get_user_profile`: that answers `{}` for a tombstoned account AND
    /// for one that never onboarded, which need opposite handling. Deliberately
    /// uncached — a stale answer here decides whether someone gets into the app.
    public func accountStatus() async throws -> AccountStatus {
        let raw: String = try await performRpc("get_account_status")
        return AccountStatus(rawValue: raw) ?? .active
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
        await invalidateProfile(userId: userId)

        return result
    }

    /// Uploads a user avatar to Supabase Storage and returns the public URL
    /// (version-stamped — see `versioned`).
    public func uploadAvatar(userId: String, imageData: Data) async throws -> URL {
        try await uploadUserImage(.userAvatars, userId: userId, imageData: imageData)
    }

    /// Uploads a user banner to Supabase Storage and returns the public URL
    /// (version-stamped — see `versioned`).
    public func uploadBanner(userId: String, imageData: Data) async throws -> URL {
        try await uploadUserImage(.userBanners, userId: userId, imageData: imageData)
    }

    /// Avatar + banner share one flow: a fixed per-user PNG path (upsert), then
    /// a version-stamped public URL so caches refetch the new image.
    private func uploadUserImage(_ bucket: StorageBucket, userId: String, imageData: Data) async throws -> URL {
        let path = try await uploadToStorage(
            bucket,
            path: "\(userId).png",
            data: imageData,
            contentType: "image/png",
            upsert: true
        )
        return Self.versioned(try client.storage.from(bucket).getPublicURL(path: path))
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

    /// The workspace file a file comment (or reply) is on — nil if it's gone
    /// or the caller can't see its folder. (`get_file_for_comment`)
    public func getFileForComment(commentId: String) async throws -> String? {
        try await performRpc("get_file_for_comment", params: ["p_comment_id": commentId])
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

    // MARK: - Social: open to collab + collab responses

    /// Whether the signed-in user is listed on the Collab map
    /// (`get_open_to_collab`). False when signed out.
    public func getOpenToCollab() async throws -> Bool {
        guard currentUserId != nil else { return false }
        return try await performRpc("get_open_to_collab")
    }

    /// Opts the signed-in user in/out of the Collab map (`set_open_to_collab`).
    public func setOpenToCollab(_ open: Bool) async throws {
        try await executeRpc("set_open_to_collab", params: ["p_open": open])
        if let uid = currentUserId { await invalidateProfile(userId: uid) }
        // The Collab map's artist list filters on this flag.
        await cache.removeAll(matching: "rpc:get_explore_artists")
    }

    /// Accepts or declines a pending collaborator relationship
    /// (`respond_to_collaborator`) — the inline actions on a notification.
    /// Returns the resulting status ("accepted" / "rejected").
    @discardableResult
    public func respondToCollaborator(relationshipId: String, accept: Bool) async throws -> String {
        struct Result: Decodable { let status: String? }
        let result: Result = try await performRpc(
            "respond_to_collaborator",
            params: ["p_relationship_id": relationshipId, "p_accept": accept]
        )
        return result.status ?? (accept ? "accepted" : "rejected")
    }

    // MARK: - Social: sign-in methods + password (Settings → Security)

    /// Which ways the account can sign in, from the auth user's identities
    /// (fetched fresh, so a just-set password shows up).
    public func signInMethods() async throws -> SignInMethods {
        do {
            let identities = try await client.auth.user().identities ?? []
            return SignInMethods(
                hasPassword: identities.contains { $0.provider == "email" },
                providers: identities.map(\.provider).filter { $0 != "email" }
            )
        } catch {
            throw mapError(error)
        }
    }

    /// Changes (or, for OAuth-only accounts, sets) the account password —
    /// mirrors the web's security section. The current password is verified
    /// with a direct token request that never touches the live session; on a
    /// true change every other session is signed out.
    public func changePassword(email: String?, currentPassword: String?, newPassword: String) async throws {
        if let currentPassword, let email {
            guard try await verifyPassword(email: email, password: currentPassword) else {
                throw PasswordChangeError.incorrectCurrentPassword
            }
        }
        do {
            try await client.auth.update(user: UserAttributes(password: newPassword))
            if currentPassword != nil {
                try? await client.auth.signOut(scope: .others)
            }
        } catch {
            throw mapError(error)
        }
    }

    /// Does a CONFIRMED account already use this email? Asks the web app's
    /// `/api/auth/email-status` (it holds the admin key the app can't), the
    /// same check the web's sign-up runs on its first step. Unconfirmed
    /// sign-ups and any failure report false, so sign-up just carries on (its
    /// own existing-account detection still catches the rest).
    public func emailHasAccount(_ email: String) async -> Bool {
        guard let url = URL(string: "https://www.volspire.com/api/auth/email-status") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return json["exists"] as? Bool ?? false
        } catch {
            return false
        }
    }

    /// True when `password` signs `email` in — a bare GoTrue password grant,
    /// so the app's own session and tokens are left alone.
    private func verifyPassword(email: String, password: String) async throws -> Bool {
        guard let url = URL(string: "\(SupabaseConfig.baseURL)/auth/v1/token?grant_type=password") else {
            throw SupabaseError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.apiKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200 ..< 300).contains(status) { return true }
            if status == 400 || status == 401 { return false }
            throw SupabaseError.unknown(status)
        } catch let error as SupabaseError {
            throw error
        } catch {
            throw mapError(error)
        }
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
        let paramsData = try rpcParamsData(params)
        let data: Data
        do {
            data = try await cache.coalescedData(cacheKey, ttl: ttl) { [self] in
                try await performRpcData(functionName, paramsData: paramsData)
            }
        } catch SupabaseError.network(let message) {
            // Offline: the last copy (even past its TTL) beats nothing — your
            // profile, its avatar link, feeds you've seen. Online errors still throw.
            if let stale: T = await cache.stale(cacheKey) {
                debugLog("[SupabaseService] rpc(\(functionName)) OFFLINE → stale cache")
                return stale
            }
            throw SupabaseError.network(message)
        }
        let value: T
        do { value = try JSONDecoder.api.decode(T.self, from: data) }
        catch {
            // Log decode failures — a 200 whose body doesn't match the DTO would
            // otherwise be SILENT (performRpcData already logged the 200 status), which
            // hides "loaded fine but UI still shimmers" bugs.
            debugLog("[SupabaseService] rpc(\(functionName)) DECODE ERROR: \(error)")
            throw mapError(error)
        }
        await cache.storeDecoded(cacheKey, value, decodedFrom: data)
        return value
    }

    // MARK: - Private

    /// Decodes an RPC's response into a DTO via the shared `.api` decoder.
    private func performRpc<T: Decodable>(_ functionName: String, params: [String: Any]? = nil) async throws -> T {
        let data = try await performRpcData(functionName, paramsData: rpcParamsData(params))
        do {
            return try JSONDecoder.api.decode(T.self, from: data)
        } catch {
            // A 200 whose body doesn't match the DTO would otherwise be silent.
            debugLog("[SupabaseService] rpc(\(functionName)) DECODE ERROR: \(error)")
            throw mapError(error)
        }
    }

    /// Runs an RPC and returns the raw response body WITHOUT decoding — the one
    /// network core every RPC variant funnels through. The coalesced cache path
    /// (`cachedRpc` → `APICache.coalescedData`) calls this directly with
    /// pre-serialized params (Data is Sendable across the cache actor's closure)
    /// and decodes once afterward, so concurrent misses share one round-trip.
    private func performRpcData(_ functionName: String, paramsData: Data?) async throws -> Data {
        do {
            let query = if let paramsData {
                // Plain JSONDecoder on purpose: `.api`'s key strategy would
                // mangle the params' snake_case keys.
                try client.rpc(functionName, params: JSONDecoder().decode(AnyJSON.self, from: paramsData))
            } else {
                try client.rpc(functionName)
            }
            let response = try await query.execute()
            debugLog("[SupabaseService] rpc(\(functionName)) status: \(response.status), bytes: \(response.data.count)")
            return response.data
        } catch {
            debugLog("[SupabaseService] rpc(\(functionName)) ERROR: \(error)")
            throw mapError(error)
        }
    }

    /// Executes an RPC whose result we don't need. `void`-returning Postgres
    /// functions reply with an empty body, and decoding `AnyJSON` from empty data
    /// throws — so these calls must run the request without decoding the response.
    private func executeRpc(_ functionName: String, params: [String: Any]? = nil) async throws {
        _ = try await performRpcData(functionName, paramsData: rpcParamsData(params))
    }

    /// Serializes an RPC params dict for the wire (failures map like any other
    /// RPC error).
    private func rpcParamsData(_ params: [String: Any]?) throws -> Data? {
        do { return try params.map { try JSONSerialization.data(withJSONObject: $0) } }
        catch { throw mapError(error) }
    }

    /// Normalizes any thrown error. Cancellation passes through as
    /// `CancellationError` (SwiftUI cancelling a `.task` / pull-to-refresh is
    /// not a failure — `Error.isCancellation` lets screens ignore it); all
    /// else becomes a `SupabaseError` whose `errorDescription` is safe to show.
    private func mapError(_ error: Error) -> any Error {
        if error.isCancellation { return CancellationError() }
        if let alreadyMapped = error as? SupabaseError { return alreadyMapped }
        if SupabaseError.isConnectionError(error) {
            return SupabaseError.network(error.localizedDescription)
        }
        if error is DecodingError {
            return SupabaseError.decodingError(error)
        }
        if let pg = error as? PostgrestError {
            // Keep the FULL dump as raw detail: `serverRawDetail` matchers
            // (`collab_rate_limited`, `listing_closed`, …) read it.
            return SupabaseError.database(code: pg.code, message: pg.message, raw: "\(error)")
        }
        return SupabaseError.serverError("\(error)")
    }
}

// MARK: - Supabase Error Types

public enum SupabaseError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case clientError(Int)
    /// An error we couldn't classify — shown as generic copy.
    case serverError(String)
    /// A Postgres/PostgREST error: the SQLSTATE `code` and the `message`
    /// (for RPCs, the `raise exception` text — our error signatures).
    case database(code: String?, message: String, raw: String)
    /// The request never got an answer (offline, timed out, DNS…).
    case network(String)
    case decodingError(Error)
    case unknown(Int)
    case fileTooLarge(maxBytes: Int)

    /// The one offline sentence (also used by `AuthManager`).
    public static let offlineMessage = "Can't reach Volspire. Check your connection and try again."
    static let genericMessage = "Something went wrong. Please try again."

    /// User-facing copy. Deliberately generic/actionable — the raw server text
    /// (Postgres / PostgREST / constraint detail) is NEVER surfaced here; it's
    /// available via `rawDetail` for logging + programmatic matching only.
    public var errorDescription: String? {
        switch self {
        case let .database(code, message, _):
            return Self.friendly(message: message, code: code)
        case .network:
            return Self.offlineMessage
        case .unauthorized:
            return "Please sign in and try again."
        case .notFound:
            return "That content is no longer available."
        case .fileTooLarge(let maxBytes):
            return FileTooLargeError(maxBytes: maxBytes).errorDescription
        case .serverError, .invalidURL, .invalidResponse, .clientError, .decodingError, .unknown:
            return Self.genericMessage
        }
    }

    /// The raw server/system detail — for logging and for code that matches specific
    /// error signatures. Never show this to users (see `errorDescription`).
    public var rawDetail: String {
        switch self {
        case .serverError(let m): return m
        case .database(_, _, let raw): return raw
        case .network(let m): return "Network error: \(m)"
        case .decodingError(let e): return e.localizedDescription
        case .invalidURL: return "invalidURL"
        case .invalidResponse: return "invalidResponse"
        case .unauthorized: return "unauthorized"
        case .notFound: return "notFound"
        case .clientError(let c): return "clientError \(c)"
        case .unknown(let c): return "unknown \(c)"
        case .fileTooLarge(let maxBytes): return "fileTooLarge \(maxBytes)"
        }
    }

    /// True for transport failures (URLSession / NSURLErrorDomain), decided by
    /// error type — never by searching message text, which matched any server
    /// error that happened to mention "connection".
    public static func isConnectionError(_ error: Error) -> Bool {
        guard !error.isCancellation else { return false }
        return error is URLError || (error as NSError).domain == NSURLErrorDomain
    }

    /// Copy for the server's known error signatures (the `raise exception`
    /// texts in our RPCs, lowercased, up to any `:` argument). Exact matches
    /// only — anything unlisted falls through to the SQLSTATE / family rules.
    private static let signatureCopy: [String: String] = [
        "not_authenticated": "Please sign in and try again.",
        "not authenticated": "Please sign in and try again.",
        "auth required": "Please sign in and try again.",
        "account_suspended": "Your account is suspended. Contact support if you think this is a mistake.",
        "user_unavailable": "You can't do that with this user.",
        "collab_rate_limited": "You're doing that a bit too fast — give it a moment and try again.",
        "collab_request_pending": "Your collab request is still waiting for a reply.",
        "collab_request_declined": "Your collab request was declined.",
        "collab_request_respond_first": "Respond to their collab request first.",
        "collab_request_you_declined": "You declined their collab request.",
        "already_collaborators": "You're already collaborators.",
        "listing_closed": "This listing is closed.",
        "username already taken": "That username is taken.",
        "unsupported_file_type": "That file type isn't supported.",
        "please confirm your email before publishing.": "Please confirm your email before publishing.",
        "forbidden_on_service_order_folder": "That can't be changed in an order folder.",
    ]

    /// Maps a database error to safe, human copy: exact signature first, then
    /// the SQLSTATE class, then our naming families (`*_too_long`,
    /// `*_required`, `*_not_found`, `not_your_*`, …). Unknown → generic.
    static func friendly(message: String, code: String?) -> String {
        let lower = message.lowercased()
        let signature = lower.split(separator: ":", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? lower
        if let copy = signatureCopy[signature] { return copy }

        switch code {
        case "23505": return "That already exists."                      // unique_violation
        case "22001": return "That's too long — please shorten it and try again." // value too long
        case "23514":                                                     // check_violation
            // Our length caps are CHECK constraints named *_length; other
            // checks (enums, ranges) aren't a "too long" problem.
            return lower.contains("length")
                ? "That's too long — please shorten it and try again."
                : genericMessage
        case "42501": return "You don't have permission to do that."     // insufficient_privilege
        case "PGRST301", "PGRST302": return "Please sign in and try again." // JWT expired / missing
        default: break
        }

        if signature.hasSuffix("_too_long") {
            return "That's too long — please shorten it and try again."
        }
        if signature.hasSuffix("_required") {
            return "Something required is missing — fill it in and try again."
        }
        if signature.hasSuffix("_not_found") || signature.hasSuffix(" not found")
            || signature.contains("not found or") {
            return "That content is no longer available."
        }
        if signature == "forbidden" || signature.hasPrefix("not_authorized") || signature.hasPrefix("not authorized")
            || signature.hasPrefix("not_your_") || signature.hasPrefix("only_") || signature == "not_a_member" {
            return "You don't have permission to do that."
        }
        if signature.hasPrefix("cannot_") || signature.hasPrefix("cannot ") {
            return "You can't do that with your own account."
        }
        return genericMessage
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
