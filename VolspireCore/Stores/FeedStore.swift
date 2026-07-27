//
//  FeedStore.swift
//  Volspire
//
//

import Foundation
import Kingfisher
import Observation
import Services
import SharedUtilities

/// Single source of truth for the Home content rails and feeds (popular /
/// demos / samples / explore feed / following) and the explore artists list.
/// Owning these here (rather than in the Home screen's view model) gives
/// mutations elsewhere in the app — upload, delete, edit, block — a direct
/// method to call, so the feed heals without notification-and-refetch hops
/// through a mounted HomeScreen. (The store still subscribes to the two
/// app-wide notifications itself, so the healing needs no view wiring at all.)
@MainActor @Observable
final class FeedStore {
    // MARK: Server state

    private(set) var loadState: LoadState = .idle

    // Sections — mirror the web app's home buckets (`get_home_tracks`).
    private(set) var popularTracks: [HomeTrack] = []
    private(set) var demos: [HomeTrack] = []
    private(set) var samples: [HomeTrack] = []

    // Explore tab data (lazy-loaded the first time each tab is opened).
    private(set) var feedTracks: [HomeTrack] = []
    private(set) var followingTracks: [HomeTrack] = []
    private(set) var artists: [ExploreArtistItem] = []
    // Defensive flags: flip on a confirmed response only, so tabs show their
    // skeleton — never "Nothing here yet" — while a fetch is in flight.
    private(set) var feedLoaded = false
    private(set) var followingLoaded = false
    private(set) var artistsLoaded = false

    /// Top popular tracks shown in the Featured carousel.
    var featuredTracks: [HomeTrack] { Array(popularTracks.prefix(5)) }

    /// Random shuffle seed for the explore feed (`get_home_feed`). Fresh per
    /// session and re-rolled on pull-to-refresh, so the recs vary instead of
    /// returning the same order every time — matching the web.
    private var feedSeed = Int.random(in: 1 ... 1_000_000)

    // MARK: Dependencies

    private let service: SupabaseService
    private let storage: StorageService
    /// Artist rows seed the shared follow overlay (set by Dependencies).
    weak var social: SocialStore?

    // MARK: In-flight guards

    private var followingLoadInFlight = false
    private var artistsLoadInFlight = false
    private var observers: [NSObjectProtocol] = []

    init(service: SupabaseService, storage: StorageService) {
        self.service = service
        self.storage = storage

        // The user published a track/listing → the rails may include it now.
        observers.append(NotificationCenter.default.addObserver(
            forName: .ownContentPosted, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case .loaded = self.loadState else { return }
                Task { await self.refreshAfterOwnPost() }
            }
        })
        // Block/unblock changes what the server returns for every read — the
        // in-memory copies are stale until refetched.
        observers.append(NotificationCenter.default.addObserver(
            forName: .userBlockStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.loadState != .idle else { return }
                Task { await self.refreshAfterBlockChange() }
            }
        })
    }

    func resetForSignOut() {
        loadState = .idle
        popularTracks = []
        demos = []
        samples = []
        feedTracks = []
        followingTracks = []
        artists = []
        feedLoaded = false
        followingLoaded = false
        artistsLoaded = false
        feedSeed = Int.random(in: 1 ... 1_000_000)
    }

    // MARK: - Loads

    /// First load — every section fetches concurrently instead of waterfalling.
    func loadInitial() async {
        async let home: Void = loadHomeData()
        async let artistRail: Void = loadArtistsIfNeeded()
        async let feed: Void = loadTracksFeedIfNeeded()
        _ = await (home, artistRail, feed)
    }

    private func loadHomeData() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let response = try await service.getHomeTracks()
            popularTracks = mapTracks(response.popularTracks)
            demos = mapTracks(response.demos)
            samples = mapTracks(response.samples)
            loadState = .loaded
            prefetchCovers(popularTracks + demos + samples)
        } catch {
            // No network / RPC failure: surface the empty/error state rather
            // than filling the screen with placeholder "seed" tracks.
            loadState = .error(error.localizedDescription)
        }
    }

    /// Pull-to-refresh for the All tab: bypass the TTL cache and re-roll the
    /// feed shuffle.
    func refreshAll() async {
        await service.invalidateHomeCaches()
        loadState = .idle
        feedLoaded = false
        feedSeed = Int.random(in: 1 ... 1_000_000)
        async let home: Void = loadHomeData()
        async let feed: Void = loadTracksFeedIfNeeded()
        _ = await (home, feed)
    }

    func loadTracksFeedIfNeeded() async {
        guard !feedLoaded else { return }
        feedLoaded = true
        do {
            feedTracks = mapTracks(try await service.getExploreTracksFeed(seed: feedSeed))
            prefetchCovers(feedTracks)
        } catch {
            feedLoaded = false
            debugLog("[FeedStore] tracks feed: \(error)")
        }
    }

    func loadFollowingIfNeeded() async {
        guard !followingLoaded, !followingLoadInFlight else { return }
        followingLoadInFlight = true
        do {
            followingTracks = mapTracks(try await service.getFollowingFeed())
            prefetchCovers(followingTracks)
            followingLoaded = true
        } catch { debugLog("[FeedStore] following: \(error)") }
        followingLoadInFlight = false
    }

    /// In-place refetch (pull) — content stays up while the fetch runs.
    func refreshFollowing() async {
        await service.invalidateHomeCaches()
        if let fresh = try? await service.getFollowingFeed() {
            followingTracks = mapTracks(fresh)
            prefetchCovers(followingTracks)
            followingLoaded = true
        }
    }

    func loadArtistsIfNeeded() async {
        guard !artistsLoaded, !artistsLoadInFlight else { return }
        artistsLoadInFlight = true
        do {
            artists = mapArtists(try await service.getExploreArtists())
            prefetchArtistAvatars(artists)
            artistsLoaded = true
        } catch { debugLog("[FeedStore] artists: \(error)") }
        artistsLoadInFlight = false
    }

    func refreshArtists() async {
        await service.invalidateHomeCaches()
        if let fresh = try? await service.getExploreArtists() {
            artists = mapArtists(fresh)
            prefetchArtistAvatars(artists)
            artistsLoaded = true
        }
    }

    // MARK: - Cross-domain events

    /// After the user posts content: refetch the rails in place, without any
    /// loading-state churn (runs off the store's own subscription).
    func refreshAfterOwnPost() async {
        await service.invalidateHomeCaches()
        if let response = try? await service.getHomeTracks() {
            popularTracks = mapTracks(response.popularTracks)
            demos = mapTracks(response.demos)
            samples = mapTracks(response.samples)
            prefetchCovers(popularTracks + demos + samples)
            loadState = .loaded
        }
    }

    /// Refetches every loaded surface after a block/unblock. Keeps the current
    /// feed seed (re-filter, not reshuffle) and only re-runs the aux tabs that
    /// had actually loaded.
    func refreshAfterBlockChange() async {
        let hadFollowing = followingLoaded
        let hadArtists = artistsLoaded
        loadState = .idle
        feedLoaded = false
        followingLoaded = false
        artistsLoaded = false
        async let home: Void = loadHomeData()
        async let feed: Void = loadTracksFeedIfNeeded()
        _ = await (home, feed)
        if hadFollowing { await loadFollowingIfNeeded() }
        if hadArtists { await loadArtistsIfNeeded() }
    }

    /// A track was deleted anywhere in the app — strip every copy so the rails
    /// can't offer a dead play. (The service invalidates the rail caches too,
    /// so a later refresh can't resurrect it.)
    func removeTrack(_ trackId: String) {
        let id = trackId.lowercased()
        popularTracks.removeAll { $0.id.lowercased() == id }
        demos.removeAll { $0.id.lowercased() == id }
        samples.removeAll { $0.id.lowercased() == id }
        feedTracks.removeAll { $0.id.lowercased() == id }
        followingTracks.removeAll { $0.id.lowercased() == id }
    }

    /// A track's metadata changed — refetch the rails in place so titles/
    /// covers are current.
    func trackEdited(_ trackId: String) async {
        await refreshAfterOwnPost()
    }

    // MARK: - Mapping + prefetch

    private func mapTracks(_ apiTracks: [ApiHomeTrack]?) -> [HomeTrack] {
        // cover_url / audio_url come back as bare `post-uploads` paths — resolve them.
        apiTracks?.map { track in
            HomeTrack(
                id: track.id,
                title: track.title,
                artist: track.artist ?? "unknown",
                coverURL: storage.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) },
                audioURL: storage.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) },
                streams: track.streams,
                durationMs: track.durationMs
            )
        } ?? []
    }

    private func mapArtists(_ items: [ApiExploreArtist]) -> [ExploreArtistItem] {
        items.map {
            // Seed the shared follow overlay (gap-fill only — this RPC is
            // cached and must not clobber fresher local knowledge). Rows
            // render from the overlay with the row flag as fallback.
            social?.seedFollow(userId: $0.userId, isFollowing: $0.isFollowing ?? false)
            return ExploreArtistItem(
                id: $0.userId,
                username: $0.username ?? "unknown",
                avatarURL: $0.profileImageUrl.flatMap { URL(string: $0) },
                monthlyListeners: $0.monthlyListeners ?? 0,
                isFollowing: $0.isFollowing ?? false
            )
        }
    }

    /// Warms the image cache for upcoming covers so they don't fetch+decode
    /// on-demand mid-scroll (the rails/grid hitch). Kingfisher skips anything
    /// already cached and decodes off the main thread.
    private func prefetchCovers(_ tracks: [HomeTrack]) {
        prefetch(tracks.compactMap(\.coverURL))
    }

    private func prefetchArtistAvatars(_ artists: [ExploreArtistItem]) {
        prefetch(artists.compactMap(\.avatarURL))
    }

    private func prefetch(_ urls: [URL]) {
        let unique = Array(Set(urls))
        guard !unique.isEmpty else { return }
        ImagePrefetcher(urls: unique).start()
    }
}
