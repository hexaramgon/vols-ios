//
//  ProfileScreenViewModel.swift
//  Volspire
//
//

import Combine
import DesignSystem
import Kingfisher
import MediaLibrary
import Observation
import Player
import Services
import SwiftUI
import SharedUtilities

// MARK: - UI Models

struct ProfileTrack: Identifiable {
    let id: String
    let title: String
    let coverURL: URL?
    let audioURL: URL?
    let streams: Int
    /// Own-profile rows surface a lock when the track isn't public.
    let isPrivate: Bool
}

/// A track owned by another artist that credits this profile's user ("Featured On").
struct CreditedTrack: Identifiable {
    let id: String
    let title: String
    let artist: String
    let artistId: String?
    let coverURL: URL?
    let audioURL: URL?
    let streams: Int
    let role: String
    /// True when the owner privatized/delisted it — renders as a tombstone row.
    let isUnavailable: Bool
    /// "delisted" | "private" — drives the tombstone label.
    let unavailableReason: String?
}

/// A sample/preset/plugin pack owned by the profile user ("Packs").
struct UserPack: Identifiable {
    let id: String
    let name: String
    let packType: String
    let price: Double
    let fileCount: Int?
    let downloads: Int
    let coverURL: URL?
    let gradient: String?
    let isPublished: Bool

    var priceLabel: String { price.priceLabel(free: true) }
}

struct ProfileService: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let serviceType: String
    let price: String
    let coverURL: URL?
    let deliveryTimeDays: Int?
    let isActive: Bool
}

// MARK: - ViewModel

@Observable @MainActor
final class ProfileScreenViewModel {
    var username: String = ""
    var bio: String = ""
    var profileImageURL: URL?
    var bannerImageURL: URL?
    var location: String = ""
    /// Role tags (Artist, Producer, …), max 3 — editable on the profile.
    var tags: [String] = []
    /// `collaborator` | `listener` — not user-editable, preserved on save.
    var accountType: String?
    /// Server base + the shared optimistic delta, so a follow toggled anywhere
    /// (this screen, Home's artist rows) moves the stat immediately — and a
    /// fresh fetch (whose count includes settled toggles) resets the delta.
    var followersCount: Int {
        guard let id = profileUserId else { return baseFollowersCount }
        return max(0, baseFollowersCount + (social?.followerDelta(id) ?? 0))
    }

    private var baseFollowersCount = 0
    var monthlyListenersCount: Int = 0
    var trackCount: Int = 0
    var tracks: [ProfileTrack] = []
    var creditedTracks: [CreditedTrack] = []
    var packs: [UserPack] = []
    var services: [ProfileService] = []
    /// Collab-board listings authored by this profile (`get_user_listings`).
    var listings: [ApiListing] = []
    /// Flip only once a response lands, so empty states never show early.
    private(set) var listingsLoaded = false
    private(set) var creditedLoaded = false
    /// Raw API rows kept so the merged "Market" tab can build marketplace nav objects.
    var apiPacks: [ApiUserPack] = []
    var apiServices: [ApiUserService] = []
    private(set) var profileUserId: String?
    /// Dominant colours pulled from the banner (or avatar) to tint the hero —
    /// the same treatment the expanded player applies to album art.
    var heroColors: [Color] = []
    var loadingState: LoadState = .idle
    /// The shared social store (assigned by the screen's `.task`) — follow and
    /// collab state route through it so Home's artist rows and this profile
    /// can't disagree.
    weak var social: SocialStore?
    /// Renders from the shared overlay (a follow made on the Home Artists tab
    /// shows here live); the profile fetch seeds the fallback.
    var isFollowing: Bool {
        guard let id = profileUserId else { return seededIsFollowing }
        return social?.isFollowing(id, fallback: seededIsFollowing) ?? seededIsFollowing
    }

    private var seededIsFollowing = false
    var isTogglingFollow: Bool = false
    /// Blocked (either direction) or suspended — the screen shows a
    /// "User unavailable" state instead of the profile.
    var isUnavailable: Bool = false
    /// The viewer blocked this user — the unavailable state offers Unblock.
    var viewerHasBlocked: Bool = false
    /// `none` | `pending` | `accepted` — collaborator relationship with the
    /// viewer. Renders from the shared overlay (an accept made in the thread
    /// shows here live); the profile fetch seeds the fallback.
    var collaboratorStatus: String {
        guard let id = profileUserId else { return seededCollabStatus }
        return social?.collabStatus(id, fallback: seededCollabStatus) ?? seededCollabStatus
    }

    private var seededCollabStatus = "none"
    /// The pair's DM id — overlay first (an in-thread accept fills it live so
    /// "Message" deep-links without a refetch), profile fetch as fallback.
    var collabConvoId: String? {
        guard let id = profileUserId else { return seededCollabConvoId }
        return social?.collabConvoId(id, fallback: seededCollabConvoId) ?? seededCollabConvoId
    }

    private var seededCollabConvoId: String?
    /// Collab-request composer state (shown when status is `none`).
    var showCollabSheet = false
    var collabMessage = ""
    var isSendingCollab = false
    var collabError: String?
    /// Shows the "Request sent!" success state inside the composer.
    var collabRequestSent = false
    /// The sender's own public tracks, attachable to the request (web parity).
    var myCollabTracks: [ProfileTrack] = []
    var isFetchingMyCollabTracks = false
    var selectedCollabTrackIds: Set<String> = []
    var collabTrackQuery = ""
    /// A collab request can attach at most 3 tracks (mirrors the web's cap).
    let maxCollabAttachments = 3

    /// Own public tracks matching the picker's search box (capped for the sheet).
    var filteredCollabTracks: [ProfileTrack] {
        let q = collabTrackQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? myCollabTracks : myCollabTracks.filter { $0.title.lowercased().contains(q) }
        return Array(base.prefix(8))
    }
    /// Drives the track "…" options sheet (own tracks only).
    var trackOptionsTrack: ProfileTrack? = nil
    /// Non-nil once `startEditingTrack` resolves — drives the edit fullScreenCover.
    var editingTrackDetail: ApiTrackDetail? = nil
    var showDeleteTrackConfirm = false
    var pendingDeleteTrackId: String? = nil

    var playerState: MediaPlayerState = .paused(media: .none)
    var cancellables = Set<AnyCancellable>()
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    private let supabaseService: SupabaseService
    private let storageService: StorageService

    init(
        supabaseService: SupabaseService = SupabaseService(),
        storageService: StorageService = StorageService()
    ) {
        self.supabaseService = supabaseService
        self.storageService = storageService
    }

    func loadProfile(userId: String) async {
        guard loadingState != .loading else { return }
        loadingState = .loading
        profileUserId = userId

        do {
            apply(try await supabaseService.getUserProfile(userId: userId))
            loadingState = .loaded
        } catch {
            loadingState = .error(error.localizedDescription)
        }
    }

    /// Background refresh (e.g. after publishing a track) — refetches and swaps
    /// the data in place WITHOUT flipping `loadingState`, so the page never
    /// drops back to the skeleton; a failed refetch keeps what's on screen.
    func refreshProfile(userId: String) async {
        guard loadingState == .loaded else { return await loadProfile(userId: userId) }
        guard let profile = try? await supabaseService.getUserProfile(userId: userId) else { return }
        apply(profile)
    }

    private func apply(_ profile: ApiUserProfile) {
        username = profile.username ?? "Unknown"
        bio = profile.bio ?? ""
        profileImageURL = profile.profileImageUrl.flatMap { URL(string: $0) }
        bannerImageURL = profile.bannerImageUrl.flatMap { URL(string: $0) }
        location = profile.location ?? ""
        tags = profile.tags ?? []
        accountType = profile.accountType
        baseFollowersCount = profile.followersCount ?? 0
        monthlyListenersCount = profile.monthlyListenersCount
        trackCount = profile.trackCount
        seededIsFollowing = profile.isFollowing ?? false
        isUnavailable = profile.isUnavailable ?? false
        viewerHasBlocked = profile.viewerHasBlocked ?? false
        seededCollabStatus = profile.collaboratorStatus ?? "none"
        seededCollabConvoId = profile.collabConvoId
        // Push the fresh per-user truth into the shared overlays (skipped for
        // ids with a toggle in flight).
        if let id = profileUserId {
            social?.reconcileFollow(userId: id, isFollowing: seededIsFollowing)
            social?.setCollabStatus(seededCollabStatus, userId: id, convoId: profile.collabConvoId)
        }
        tracks = profile.tracks.map(profileTrack)
        apiServices = profile.services
        services = profile.services.map { mapService($0) }
    }

    /// Maps a profile API track row to the UI model, resolving bare
    /// `post-uploads` paths to full public URLs. (Was written twice —
    /// `apply` and `loadMyTracksForCollab`.)
    private func profileTrack(_ track: ApiProfileTrack) -> ProfileTrack {
        ProfileTrack(
            id: track.id,
            title: track.title,
            coverURL: storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) },
            audioURL: storageService.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) },
            streams: track.streams ?? 0,
            isPrivate: (track.visibility ?? "public") != "public"
        )
    }

    /// Loads "Featured On" — tracks by other artists that credit this user.
    /// Prefetch every tab's cover art so switching tabs shows already-cached images
    /// that slide in with the page instead of popping in mid-transition.
    func prefetchTabCovers() {
        let urls = tracks.compactMap(\.coverURL)
            + creditedTracks.compactMap(\.coverURL)
            + packs.compactMap(\.coverURL)
            + services.compactMap(\.coverURL)
        guard !urls.isEmpty else { return }
        ImagePrefetcher(urls: Array(Set(urls))).start()
    }

    func loadCreditedTracks(userId: String) async {
        do {
            let rows = try await supabaseService.getTracksCreditedToUser(userId: userId)
            creditedTracks = rows.map { row in
                CreditedTrack(
                    id: row.id,
                    title: row.title,
                    artist: row.artist ?? "",
                    artistId: row.artistId,
                    coverURL: storageService.resolveTrackUrl(row.coverUrl).flatMap { URL(string: $0) },
                    audioURL: storageService.resolveTrackUrl(row.audioUrl).flatMap { URL(string: $0) },
                    streams: row.streams ?? 0,
                    role: row.role ?? "",
                    isUnavailable: row.isUnavailable ?? false,
                    unavailableReason: row.unavailableReason
                )
            }
            creditedLoaded = true
        } catch {
            debugLog("[ProfileVM] Failed to load credited tracks: \(error)")
        }
    }

    /// Loads the user's collab-board listings for the merged "Market" tab.
    func loadUserListings(userId: String) async {
        do {
            listings = try await supabaseService.getUserListings(userId: userId)
            listingsLoaded = true
        } catch {
            debugLog("[ProfileVM] Failed to load listings: \(error)")
        }
    }

    /// Builds a marketplace pack/service (for navigating to its detail) from the
    /// raw profile rows kept above.
    func marketplacePack(id: String) -> ApiMarketplacePack? {
        apiPacks.first { $0.packId == id }?.asMarketplacePack(
            creatorUserId: profileUserId, creatorUsername: username,
            creatorImageUrl: profileImageURL?.absoluteString
        )
    }

    func marketplaceService(id: String) -> ApiMarketplaceService? {
        apiServices.first { $0.serviceId == id }?.asMarketplaceService(
            artistUserId: profileUserId, artistUsername: username,
            artistImageUrl: profileImageURL?.absoluteString
        )
    }

    /// True when the merged Market tab has anything to show.
    var hasMarketItems: Bool { !packs.isEmpty || !services.isEmpty || !listings.isEmpty }

    /// Loads the user's sample/preset/plugin packs.
    func loadPacks(userId: String) async {
        do {
            let rows = try await supabaseService.getUserPacks(userId: userId)
            apiPacks = rows
            packs = rows.map { row in
                UserPack(
                    id: row.packId,
                    name: row.name,
                    packType: row.packType ?? "Pack",
                    price: row.price ?? 0,
                    fileCount: row.fileCount,
                    downloads: row.downloads ?? 0,
                    coverURL: storageService.resolveTrackUrl(row.coverUrl).flatMap { URL(string: $0) },
                    gradient: row.gradient,
                    isPublished: row.isPublished ?? true
                )
            }
        } catch {
            debugLog("[ProfileVM] Failed to load packs: \(error)")
        }
    }

    /// Extracts dominant colours from the banner (falling back to the avatar) to
    /// tint the hero — mirrors `MediaMeta.colors` / the expanded player's theming.
    func loadHeroColors() async {
        guard let source = bannerImageURL ?? profileImageURL else { return }
        // .fair, not .high — feeds a blurred hero tint; see MediaMeta.colors.
        let extracted = await source.image?
            .dominantColorFrequencies(with: .fair)?
            .map { Color(uiColor: $0.color) }
        if let extracted, !extracted.isEmpty {
            heroColors = extracted
        }
    }

    /// Fetches the full track detail and opens the edit fullScreenCover.
    func startEditingTrack(_ trackId: String) async {
        do {
            editingTrackDetail = try await supabaseService.getTrackMetadata(trackId: trackId)
        } catch {
            debugLog("[ProfileVM] Failed to load track for editing: \(error)")
        }
    }

    /// Re-fetches one track's detail after an edit and patches it into `tracks`
    /// in place — avoids a full-page reload (and its skeleton flash) for a
    /// single-row edit. `updateTrack` already invalidated the cache, so this is
    /// guaranteed fresh.
    func refreshTrack(trackId: String) async {
        guard let idx = tracks.firstIndex(where: { $0.id == trackId }) else { return }
        do {
            let detail = try await supabaseService.getTrackMetadata(trackId: trackId)
            let t = tracks[idx]
            tracks[idx] = ProfileTrack(
                id: t.id,
                title: detail.title,
                coverURL: storageService.resolveTrackUrl(detail.coverUrl).flatMap { URL(string: $0) },
                audioURL: t.audioURL,
                streams: t.streams,
                isPrivate: (detail.visibility ?? "public") != "public"
            )
        } catch {
            debugLog("[ProfileVM] Failed to refresh track: \(error)")
        }
    }

    /// Soft-deletes a track and drops it from the local list.
    func deleteTrack(trackId: String) async -> Bool {
        guard let userId = profileUserId else { return false }
        do {
            try await supabaseService.deleteTrack(trackId: trackId, userId: userId)
            tracks.removeAll { $0.id == trackId }
            trackCount = max(0, trackCount - 1)
            return true
        } catch {
            debugLog("[ProfileVM] Failed to delete track: \(error)")
            return false
        }
    }

    /// Toggles a track's visibility (the "Hide"/"Unhide" quick action).
    func hideTrack(trackId: String, hide: Bool) async -> Bool {
        guard let userId = profileUserId else { return false }
        let visibility = hide ? "private" : "public"
        do {
            try await supabaseService.updateTrackVisibility(trackId: trackId, visibility: visibility, userId: userId)
            if let idx = tracks.firstIndex(where: { $0.id == trackId }) {
                let t = tracks[idx]
                tracks[idx] = ProfileTrack(
                    id: t.id, title: t.title, coverURL: t.coverURL, audioURL: t.audioURL,
                    streams: t.streams, isPrivate: hide
                )
            }
            return true
        } catch {
            debugLog("[ProfileVM] Failed to update track visibility: \(error)")
            return false
        }
    }

    private func mapService(_ svc: ApiUserService) -> ProfileService {
        let priceStr: String
        if let p = svc.price {
            priceStr = p.priceLabel(currency: svc.currency)
        } else {
            priceStr = "N/A"
        }
        return ProfileService(
            id: svc.id,
            title: svc.title,
            description: svc.description ?? "",
            serviceType: svc.serviceType ?? "",
            price: priceStr,
            coverURL: storageService.resolveTrackUrl(svc.coverUrl).flatMap { URL(string: $0) },
            deliveryTimeDays: svc.deliveryTimeDays,
            isActive: svc.isActive ?? true
        )
    }

    /// Resets the composer to a fresh state (called when the sheet opens).
    func resetCollabComposer() {
        collabMessage = ""
        selectedCollabTrackIds = []
        collabTrackQuery = ""
        collabError = nil
        collabRequestSent = false
    }

    /// Loads the sender's own public tracks so they can attach a few to the request.
    /// Only public tracks are attachable — the recipient (not the owner/a buyer)
    /// can't open a private/delisted track, mirroring the web's picker filter.
    func loadMyTracksForCollab(currentUserId: String) async {
        guard myCollabTracks.isEmpty, !currentUserId.isEmpty, !isFetchingMyCollabTracks else { return }
        isFetchingMyCollabTracks = true
        defer { isFetchingMyCollabTracks = false }
        do {
            let profile = try await supabaseService.getUserProfile(userId: currentUserId)
            myCollabTracks = profile.tracks
                .filter { ($0.visibility ?? "public") == "public" }
                .map(profileTrack)
        } catch {
            debugLog("[ProfileVM] loadMyTracksForCollab failed: \(error)")
        }
    }

    /// Toggles a track in/out of the attachment set, enforcing the 3-track cap.
    func toggleCollabTrack(_ id: String) {
        if selectedCollabTrackIds.contains(id) {
            selectedCollabTrackIds.remove(id)
        } else if selectedCollabTrackIds.count < maxCollabAttachments {
            selectedCollabTrackIds.insert(id)
        }
    }

    /// Whether the composer can submit — a pitch or at least one attached track.
    var canSendCollab: Bool {
        let hasMessage = !collabMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasMessage || !selectedCollabTrackIds.isEmpty) && !isSendingCollab
    }

    /// Sends a collaboration request. The pitch is optional, but selected tracks
    /// are both passed as `p_track_ids` and appended to the message as links (web
    /// parity). On success the status flips to `pending` and the success state shows.
    func sendCollab(userId: String) async -> Bool {
        guard canSendCollab else { return false }
        let trimmed = collabMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let trackIds = Array(selectedCollabTrackIds)

        // The message is just the pitch — the attached tracks are sent as
        // structured references (`p_track_ids` → requests.metadata.track_ids) and
        // rendered as cards on the client. No inline URLs.
        isSendingCollab = true
        collabError = nil
        defer { isSendingCollab = false }
        do {
            try await supabaseService.sendCollabRequest(
                targetId: userId,
                message: trimmed,
                trackIds: trackIds.isEmpty ? nil : trackIds
            )
            seededCollabStatus = "pending"
            social?.setCollabStatus("pending", userId: userId)
            collabRequestSent = true
            return true
        } catch {
            let text = "\(error)".lowercased()
            if text.contains("collab_rate_limited") {
                collabError = "You can only send one collab request to this artist per week."
            } else if text.contains("attachment") {
                collabError = "A collab request can attach at most 3 items."
            } else {
                collabError = "Couldn't send your request. Please try again."
            }
            debugLog("[ProfileVM] sendCollab failed: \(error)")
            return false
        }
    }

    /// Ends an accepted collaboration: the backend deletes the relationship and
    /// archives the pair's DM for this user; locally the Collab button and the
    /// hero badge reset immediately.
    func removeCollaborator(userId: String) async {
        guard collaboratorStatus == "accepted" else { return }
        do {
            try await supabaseService.removeCollaborator(userId: userId)
            seededCollabStatus = "none"
            seededCollabConvoId = nil
            social?.setCollabStatus("none", userId: userId)
        } catch {
            debugLog("[ProfileVM] removeCollaborator failed: \(error)")
        }
    }

    func toggleFollow(userId: String) async {
        guard !isTogglingFollow, let social else { return }
        isTogglingFollow = true
        // The store flips the shared overlay AND the follower-count delta
        // optimistically, rolling both back on failure — `followersCount`
        // renders base + delta, so there's no local math to keep in sync.
        await social.toggleFollow(userId: userId, currentlyFollowing: isFollowing)
        isTogglingFollow = false
    }

    func play(_ track: ProfileTrack) {
        guard let player, track.audioURL != nil else { return }
        // `MediaPlayer.play(_:queue:)` registers the queue with MediaState
        // first (deduped, nil-audio dropped) — the invariant this view model
        // used to hand-roll.
        Task { await player.play(MediaID(track.id), queue: tracks.map(mediaFor)) }
    }

    private func mediaFor(_ track: ProfileTrack) -> Media {
        Media(
            id: MediaID(track.id),
            meta: MediaMeta(
                artwork: track.coverURL,
                title: track.title,
                artist: username,
                audioURL: track.audioURL
            )
        )
    }

    /// Plays a "Featured On" track, queueing the remaining available credits.
    func playCredited(_ track: CreditedTrack) {
        guard let player, !track.isUnavailable else { return }
        let queue = creditedTracks.filter { !$0.isUnavailable }.map { t in
            Media(
                id: MediaID(t.id),
                meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL)
            )
        }
        Task { await player.play(MediaID(track.id), queue: queue) }
    }

    var profileUpdateError: String? = nil

    /// Uploads a new avatar to storage and reflects it locally. Persisted to the
    /// DB on the next `saveProfile` (the web uploads-then-saves the same way).
    func uploadAvatar(userId: String, imageData: Data) async -> Bool {
        do {
            profileImageURL = try await supabaseService.uploadAvatar(userId: userId, imageData: imageData)
            return true
        } catch {
            debugLog("[ProfileVM] Failed to upload avatar: \(error)")
            return false
        }
    }

    /// Uploads a new banner to storage and reflects it locally (see `uploadAvatar`).
    func uploadBanner(userId: String, imageData: Data) async -> Bool {
        do {
            bannerImageURL = try await supabaseService.uploadBanner(userId: userId, imageData: imageData)
            return true
        } catch {
            debugLog("[ProfileVM] Failed to upload banner: \(error)")
            return false
        }
    }

    /// Saves the whole profile in one `update_user` call. Because the RPC writes
    /// every field as-passed (no COALESCE except account_type), we send the
    /// current image URLs + preserved account type so nothing gets wiped.
    /// Whether a handle is free, or nil when the check itself failed (offline) —
    /// callers treat nil as "don't know", never as "taken", so a flaky network
    /// can't block a legitimate rename. Keeps `supabaseService` private, matching
    /// how the edit screen reaches everything else.
    func isUsernameAvailable(_ username: String) async -> Bool? {
        try? await supabaseService.checkUsernameAvailable(username)
    }

    func saveProfile(userId: String, username: String, bio: String, location: String, tags: [String]) async -> Bool {
        do {
            let result = try await supabaseService.updateUserProfile(
                userId: userId,
                username: username,
                bio: bio.isEmpty ? nil : bio,
                accountType: accountType,
                location: location.isEmpty ? nil : location,
                profileImageUrl: profileImageURL?.absoluteString,
                bannerImageUrl: bannerImageURL?.absoluteString,
                tags: tags.isEmpty ? nil : tags
            )
            self.username = result.username ?? username
            self.bio = result.bio ?? bio
            self.location = result.location ?? location
            self.tags = result.tags ?? tags
            self.accountType = result.accountType ?? accountType
            profileUpdateError = nil
            // Own identity changed — refresh the shared profile so the tab-bar
            // avatar and every own-identity surface pick it up.
            await social?.refreshMyProfile()
            return true
        } catch {
            // `update_user` fails the `users_username_key` unique index when the
            // handle is taken. The shared mapper only knows to say "That already
            // exists", which doesn't tell the user WHICH field or what to do —
            // so name it here. Everything else keeps the mapped copy.
            let raw = ((error as? SupabaseError)?.rawDetail ?? "\(error)").lowercased()
            if raw.contains("users_username_key") || raw.contains("username already taken")
                || ((raw.contains("duplicate") || raw.contains("unique constraint")) && raw.contains("username"))
            {
                profileUpdateError = "That username is already taken — try another."
            } else {
                profileUpdateError = error.localizedDescription
            }
            debugLog("[ProfileVM] Failed to save profile: \(error)")
            return false
        }
    }
}

extension ProfileScreenViewModel: PlayerStateObserving {}
