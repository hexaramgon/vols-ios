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

    var priceLabel: String { price <= 0 ? "Free" : "$\(price == price.rounded() ? String(format: "%.0f", price) : String(format: "%.2f", price))" }
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

enum ProfileLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
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
    var followersCount: Int = 0
    var monthlyListenersCount: Int = 0
    var trackCount: Int = 0
    var tracks: [ProfileTrack] = []
    var creditedTracks: [CreditedTrack] = []
    var packs: [UserPack] = []
    var services: [ProfileService] = []
    /// Collab-board listings authored by this profile (`get_user_listings`).
    var listings: [ApiListing] = []
    /// Raw API rows kept so the merged "Market" tab can build marketplace nav objects.
    var apiPacks: [ApiUserPack] = []
    var apiServices: [ApiUserService] = []
    private(set) var profileUserId: String?
    /// Dominant colours pulled from the banner (or avatar) to tint the hero —
    /// the same treatment the expanded player applies to album art.
    var heroColors: [Color] = []
    var loadingState: ProfileLoadingState = .idle
    var isFollowing: Bool = false
    var isTogglingFollow: Bool = false
    /// `none` | `pending` | `accepted` — collaborator relationship with the viewer.
    var collaboratorStatus: String = "none"
    var collabConvoId: String?
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
    var showCreateService: Bool = false
    var isCreatingService: Bool = false
    var editingService: ProfileService? = nil
    var isEditingService: Bool = false

    /// Drives the track "…" options sheet (own tracks only).
    var trackOptionsTrack: ProfileTrack? = nil
    /// Non-nil once `startEditingTrack` resolves — drives the edit fullScreenCover.
    var editingTrackDetail: ApiTrackDetail? = nil
    var showDeleteTrackConfirm = false
    var pendingDeleteTrackId: String? = nil

    var latestRelease: ProfileTrack? {
        tracks.first
    }

    var curatedTracks: [ProfileTrack] {
        Array(tracks.dropFirst())
    }

    weak var mediaState: MediaState?
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
            let profile = try await supabaseService.getUserProfile(userId: userId)

            username = profile.username ?? "Unknown"
            bio = profile.bio ?? ""
            profileImageURL = profile.profileImageUrl.flatMap { URL(string: $0) }
            bannerImageURL = profile.bannerImageUrl.flatMap { URL(string: $0) }
            location = profile.location ?? ""
            tags = profile.tags ?? []
            accountType = profile.accountType
            followersCount = profile.followersCount ?? 0
            monthlyListenersCount = profile.monthlyListenersCount
            trackCount = profile.trackCount
            isFollowing = profile.isFollowing ?? false
            collaboratorStatus = profile.collaboratorStatus ?? "none"
            collabConvoId = profile.collabConvoId
            tracks = profile.tracks.map { track in
                // Resolve bare `post-uploads` paths to full public URLs.
                ProfileTrack(
                    id: track.id,
                    title: track.title,
                    coverURL: storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) },
                    audioURL: storageService.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) },
                    streams: track.streams ?? 0,
                    isPrivate: (track.visibility ?? "public") != "public"
                )
            }
            apiServices = profile.services
            services = profile.services.map { mapService($0) }
            loadingState = .loaded
        } catch {
            loadingState = .error(error.localizedDescription)
        }
    }

    /// Loads "Featured On" — tracks by other artists that credit this user.
    /// Prefetch every tab's cover art so switching tabs shows already-cached images
    /// that slide in with the page instead of popping in mid-transition.
    func prefetchTabCovers() {
        let urls = curatedTracks.compactMap(\.coverURL)
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
        } catch {
            print("[ProfileVM] Failed to load credited tracks: \(error)")
        }
    }

    /// Loads the user's collab-board listings for the merged "Market" tab.
    func loadUserListings(userId: String) async {
        do {
            listings = try await supabaseService.getUserListings(userId: userId)
        } catch {
            print("[ProfileVM] Failed to load listings: \(error)")
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
            print("[ProfileVM] Failed to load packs: \(error)")
        }
    }

    /// Extracts dominant colours from the banner (falling back to the avatar) to
    /// tint the hero — mirrors `MediaMeta.colors` / the expanded player's theming.
    func loadHeroColors() async {
        guard let source = bannerImageURL ?? profileImageURL else { return }
        let extracted = await source.image?
            .dominantColorFrequencies(with: .high)?
            .map { Color(uiColor: $0.color) }
        if let extracted, !extracted.isEmpty {
            heroColors = extracted
        }
    }

    func createService(title: String, description: String, serviceType: String, price: Double, currency: String, deliveryTimeDays: Int?) async {
        guard !isCreatingService else { return }
        isCreatingService = true
        do {
            let svc = try await supabaseService.createUserService(
                title: title,
                description: description,
                serviceType: serviceType,
                price: price,
                currency: currency,
                deliveryTimeDays: deliveryTimeDays
            )
            services.append(mapService(svc))
            showCreateService = false
        } catch {
            print("[ProfileVM] Failed to create service: \(error)")
        }
        isCreatingService = false
    }

    func updateService(serviceId: String, title: String, description: String, serviceType: String, price: Double, currency: String, deliveryTimeDays: Int?) async {
        guard !isEditingService else { return }
        isEditingService = true
        do {
            let svc = try await supabaseService.updateUserService(
                serviceId: serviceId,
                title: title,
                description: description,
                serviceType: serviceType,
                price: price,
                currency: currency,
                deliveryTimeDays: deliveryTimeDays,
                isActive: nil
            )
            if let idx = services.firstIndex(where: { $0.id == serviceId }) {
                services[idx] = mapService(svc)
            }
            editingService = nil
        } catch {
            print("[ProfileVM] Failed to update service: \(error)")
        }
        isEditingService = false
    }

    /// Fetches the full track detail and opens the edit fullScreenCover.
    func startEditingTrack(_ trackId: String) async {
        do {
            editingTrackDetail = try await supabaseService.getTrackMetadata(trackId: trackId)
        } catch {
            print("[ProfileVM] Failed to load track for editing: \(error)")
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
            print("[ProfileVM] Failed to refresh track: \(error)")
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
            print("[ProfileVM] Failed to delete track: \(error)")
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
            print("[ProfileVM] Failed to update track visibility: \(error)")
            return false
        }
    }

    private func mapService(_ svc: ApiUserService) -> ProfileService {
        let priceStr: String
        if let p = svc.price {
            let symbols = ["USD": "$", "EUR": "€", "GBP": "£"]
            let sym = symbols[svc.currency ?? "USD"] ?? (svc.currency ?? "$")
            priceStr = "\(sym)\(String(format: p == p.rounded() ? "%.0f" : "%.2f", p))"
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
                .map { track in
                    ProfileTrack(
                        id: track.id,
                        title: track.title,
                        coverURL: storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) },
                        audioURL: storageService.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) },
                        streams: track.streams ?? 0,
                        isPrivate: false
                    )
                }
        } catch {
            print("[ProfileVM] loadMyTracksForCollab failed: \(error)")
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
            collaboratorStatus = "pending"
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
            print("[ProfileVM] sendCollab failed: \(error)")
            return false
        }
    }

    func toggleFollow(userId: String) async {
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        // Optimistically flip the state + count, rolling back on failure
        // (mirrors the web app's handleToggleFollow).
        let next = !isFollowing
        isFollowing = next
        followersCount = max(0, followersCount + (next ? 1 : -1))
        AnalyticsService.shared?.log(next ? .userFollowed : .userUnfollowed, metadata: ["target_user_id": .string(userId)])
        do {
            try await supabaseService.toggleFollow(targetUser: userId)
        } catch {
            isFollowing = !next
            followersCount = max(0, followersCount + (next ? -1 : 1))
            print("[ProfileVM] Failed to toggle follow: \(error)")
        }
        isTogglingFollow = false
    }

    func play(_ track: ProfileTrack) {
        guard let player, track.audioURL != nil else { return }
        // Register every playable track with the library and AWAIT that before
        // starting playback. `MediaPlayer.play` rejects a queue whose items
        // aren't in `MediaState` — calling it before `addTrack` resolves is why
        // a fresh tap (no prior playback) did nothing.
        Task {
            var seen = Set<String>()
            let queue = tracks.filter { $0.audioURL != nil && seen.insert($0.id).inserted }
            for t in queue { await mediaState?.addTrack(mediaFor(t)) }
            player.play(MediaID(track.id), of: queue.map { MediaID($0.id) })
        }
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
        // Same fix as `play`: add the whole queue to the library and await it
        // before starting playback.
        Task {
            var seen = Set<String>()
            let queue = creditedTracks.filter { !$0.isUnavailable && seen.insert($0.id).inserted }
            for t in queue {
                await mediaState?.addTrack(
                    Media(
                        id: MediaID(t.id),
                        meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL)
                    )
                )
            }
            player.play(MediaID(track.id), of: queue.map { MediaID($0.id) })
        }
    }

    var profileUpdateError: String? = nil

    /// Uploads a new avatar to storage and reflects it locally. Persisted to the
    /// DB on the next `saveProfile` (the web uploads-then-saves the same way).
    func uploadAvatar(userId: String, imageData: Data) async -> Bool {
        do {
            profileImageURL = try await supabaseService.uploadAvatar(userId: userId, imageData: imageData)
            return true
        } catch {
            print("[ProfileVM] Failed to upload avatar: \(error)")
            return false
        }
    }

    /// Uploads a new banner to storage and reflects it locally (see `uploadAvatar`).
    func uploadBanner(userId: String, imageData: Data) async -> Bool {
        do {
            bannerImageURL = try await supabaseService.uploadBanner(userId: userId, imageData: imageData)
            return true
        } catch {
            print("[ProfileVM] Failed to upload banner: \(error)")
            return false
        }
    }

    /// Saves the whole profile in one `update_user` call. Because the RPC writes
    /// every field as-passed (no COALESCE except account_type), we send the
    /// current image URLs + preserved account type so nothing gets wiped.
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
            return true
        } catch {
            profileUpdateError = error.localizedDescription
            print("[ProfileVM] Failed to save profile: \(error)")
            return false
        }
    }
}

extension ProfileScreenViewModel: PlayerStateObserving {}
