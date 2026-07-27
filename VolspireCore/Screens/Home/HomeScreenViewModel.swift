//
//  HomeScreenViewModel.swift
//  Volspire
//
//  Created by GitHub Copilot on 01.02.2026.
//

import DesignSystem
import Foundation
import Kingfisher
import MediaLibrary
import Player
import Services
import SharedUtilities
import SwiftUI

// MARK: - UI Models

/// One collaborator's recent workspace actions, for the stories-style
/// Recent Activity rail (avatar circle → tap → their past-month history).
struct HomeTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let coverURL: URL?
    let audioURL: URL?
    let streams: Int?
    let durationMs: Int?
}

struct ExploreArtistItem: Identifiable {
    let id: String
    let username: String
    let avatarURL: URL?
    let monthlyListeners: Int
    var isFollowing: Bool
}

// MARK: - ViewModel

@Observable
@MainActor
class HomeScreenViewModel {
    var loadingState: LoadState = .idle

    // Sections — mirror the web app's home buckets (`get_home_tracks`).
    var popularTracks: [HomeTrack] = []
    var demos: [HomeTrack] = []
    var samples: [HomeTrack] = []

    // Explore tab data (lazy-loaded the first time each tab is opened).
    var feedTracks: [HomeTrack] = []
    var followingTracks: [HomeTrack] = []
    var artists: [ExploreArtistItem] = []
    var feedLoaded = false
    var followingLoaded = false
    var artistsLoaded = false


    // Create-folder sheet on the Workspace tab. The folders themselves live in
    // the shared WorkspaceStore; only the form state is screen-local.
    var showCreateFolder = false
    var newFolderName = ""
    var newFolderDescription = ""
    var isCreatingFolder = false
    /// The shared workspace store — assigned by HomeScreen's `.task`.
    weak var workspace: WorkspaceStore?
    /// The shared social store — artist rows seed its follow overlay.
    weak var social: SocialStore?
    /// The shared listings store — the Collab tab/rail render from it; these
    /// passthroughs exist so pull-refreshes still drive the floating chip.
    weak var listingsStore: ListingsStore?

    /// Random shuffle seed for the explore feed (`get_home_feed`). Fresh per VM
    /// (i.e. per app session) and re-rolled on pull-to-refresh, so the recs vary
    /// instead of returning the same order every time — matching the web.
    private var feedSeed = Int.random(in: 1 ... 1_000_000)

    /// Top popular tracks shown in the Featured carousel.
    var featuredTracks: [HomeTrack] { Array(popularTracks.prefix(5)) }

    weak var player: MediaPlayer?

    private let supabaseService: SupabaseService
    private let storageService: StorageService

    init(
        supabaseService: SupabaseService = SupabaseService(),
        storageService: StorageService = StorageService()
    ) {
        self.supabaseService = supabaseService
        self.storageService = storageService
    }

    /// Plays `track` and queues the rest of the section it came from (`context`)
    /// in its natural order, so Next/Previous move through *that* section — not a
    /// concatenation of every home rail (which is why Next used to jump to the
    /// top "Popular" tracks). Registration in MediaState, id dedupe and dropping
    /// nil-audio items all live in the shared `MediaPlayer.play(_:queue:)`.
    func playTrack(_ track: HomeTrack, in context: [HomeTrack]) async {
        guard track.audioURL != nil else { return }

        // Queue = the section in order. The tapped track must be in it (it is,
        // since it came from that list) or `MediaPlayer.play` rejects the queue.
        var ordered = context
        if !ordered.contains(where: { $0.id == track.id }) { ordered = [track] }

        await player?.play(MediaID(track.id), queue: ordered.map { t in
            Media(
                id: MediaID(t.id),
                meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL)
            )
        })
    }

    /// Load home data from Supabase
    func loadHomeData() async {
        guard loadingState != .loading else { return }

        loadingState = .loading

        do {
            let response = try await supabaseService.getHomeTracks()
            popularTracks = mapTracks(response.popularTracks)
            demos = mapTracks(response.demos)
            samples = mapTracks(response.samples)
            loadingState = .loaded
            prefetchCovers(popularTracks + demos + samples)
        } catch {
            // No network / RPC failure: surface the empty/error state rather than
            // filling the screen with placeholder "seed" tracks.
            loadingState = .error(error.localizedDescription)
        }
    }

    /// First load — every section fetches concurrently instead of waterfalling.
    func loadInitial() async {
        async let home: Void = loadHomeData()
        async let artistRail: Void = loadArtists()
        async let feed: Void = loadTracksFeed()
        // Collab listings also feed the "All" tab's Collab rail (not just the
        // Collab tab), so warm the shared store on first load — its load is
        // guarded, so opening the Collab tab afterwards is a no-op.
        async let listings: Void = warmListings()
        _ = await (home, artistRail, feed, listings)
    }

    private func warmListings() async {
        await listingsStore?.loadListingsIfNeeded()
    }

    /// True while any pull-to-refresh is running. The system's refresh spinner
    /// anchors at the scroll view's very top — hidden behind the fixed header —
    /// so the screen floats its own indicator below the header off this flag.
    var isPullRefreshing = false
    private var pullRefreshCount = 0 {
        didSet { isPullRefreshing = pullRefreshCount > 0 }
    }

    func refresh() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await supabaseService.invalidateHomeCaches() // bypass the TTL cache — a pull means "fetch fresh"
        loadingState = .idle
        feedLoaded = false
        feedSeed = Int.random(in: 1 ... 1_000_000) // fresh shuffle on pull-to-refresh
        async let home: Void = loadHomeData()
        async let feed: Void = loadTracksFeed()
        // The All tab also shows the Collab rail, so refresh listings with it.
        async let listings: Void = refreshListings()
        _ = await (home, feed, listings)
    }

    // MARK: - Pull-to-refresh (aux tabs)

    // In-place refetchers: the tab keeps showing its current content while the
    // fetch is in flight, and only a confirmed response replaces it — a pull
    // never drops a tab back to its skeleton (see the defensive-loading rule).

    func refreshFollowing() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await supabaseService.invalidateHomeCaches()
        if let fresh = try? await supabaseService.getFollowingFeed() {
            followingTracks = mapTracks(fresh)
            prefetchCovers(followingTracks)
            followingLoaded = true
        }
    }

    func refreshArtists() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await supabaseService.invalidateHomeCaches()
        if let fresh = try? await supabaseService.getExploreArtists() {
            artists = mapArtists(fresh)
            prefetchArtistAvatars(artists)
            artistsLoaded = true
        }
    }

    func refreshListings() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await listingsStore?.refreshListings()
    }

    /// After the user posts content (track or listing, `ownContentPosted`):
    /// refetch the home rails in place, without any loading-state churn.
    /// (Listings refresh themselves — ListingsStore subscribes to the same
    /// notification.)
    func refreshAfterOwnPost() async {
        await supabaseService.invalidateHomeCaches()
        if let response = try? await supabaseService.getHomeTracks() {
            popularTracks = mapTracks(response.popularTracks)
            demos = mapTracks(response.demos)
            samples = mapTracks(response.samples)
            prefetchCovers(popularTracks + demos + samples)
            loadingState = .loaded
        }
    }

    /// Refetches every loaded server surface after a block/unblock — the server
    /// filters the blocked party out of each read, so the in-memory copies are
    /// stale. Keeps the current feed seed (re-filter, not reshuffle) and only
    /// re-runs the aux tabs that had actually loaded.
    func refreshAfterBlockChange() async {
        let hadFollowing = followingLoaded
        let hadArtists = artistsLoaded
        loadingState = .idle
        feedLoaded = false
        followingLoaded = false
        artistsLoaded = false
        async let home: Void = loadHomeData()
        async let feed: Void = loadTracksFeed()
        _ = await (home, feed)
        if hadFollowing { await loadFollowing() }
        if hadArtists { await loadArtists() }
        // Listings refresh themselves — ListingsStore subscribes to the same
        // notification.
    }

    // MARK: - Explore tabs

    func loadTracksFeed() async {
        guard !feedLoaded else { return }
        feedLoaded = true
        do { feedTracks = mapTracks(try await supabaseService.getExploreTracksFeed(seed: feedSeed)); prefetchCovers(feedTracks) }
        catch { feedLoaded = false; debugLog("[HomeVM] tracks feed: \(error)") }
    }

    /// Re-entry guard — separate from `followingLoaded`, which must stay false
    /// (skeleton showing) until a response actually arrives, so the tab never
    /// flashes "Nothing here yet" mid-fetch (defensive empty states).
    private var followingLoadInFlight = false

    func loadFollowing() async {
        guard !followingLoaded, !followingLoadInFlight else { return }
        followingLoadInFlight = true
        do {
            followingTracks = mapTracks(try await supabaseService.getFollowingFeed())
            prefetchCovers(followingTracks)
            followingLoaded = true
        } catch { debugLog("[HomeVM] following: \(error)") }
        followingLoadInFlight = false
    }

    /// Workspace-tab pull-to-refresh: delegates to the shared store, wrapped in
    /// the pull-refresh counter so the floating chip shows like the other tabs.
    func refreshFolders() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await workspace?.refreshFolders()
    }

    /// Creates a folder from the Workspace tab's CTA / grid tile via the shared
    /// store (which refetches the grid in place) — same trim + guard behaviour
    /// as the Workspace screen.
    func createFolder() async {
        guard let workspace, !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isCreatingFolder = true
        do {
            let desc = newFolderDescription.trimmingCharacters(in: .whitespaces)
            try await workspace.createFolder(
                name: newFolderName.trimmingCharacters(in: .whitespaces),
                description: desc.isEmpty ? nil : desc
            )
            newFolderName = ""
            newFolderDescription = ""
            showCreateFolder = false
        } catch {
            debugLog("[HomeVM] createFolder: \(error)")
        }
        isCreatingFolder = false
    }

    /// Same defensive shape as `loadFollowing` — flag flips on response only.
    private var artistsLoadInFlight = false

    func loadArtists() async {
        guard !artistsLoaded, !artistsLoadInFlight else { return }
        artistsLoadInFlight = true
        do {
            artists = mapArtists(try await supabaseService.getExploreArtists())
            prefetchArtistAvatars(artists)
            artistsLoaded = true
        } catch { debugLog("[HomeVM] artists: \(error)") }
        artistsLoadInFlight = false
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

    /// Pull-to-refresh for the Saved list, chip-wrapped like the board's.
    func refreshSavedListings() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await listingsStore?.refreshSaved()
    }

    // MARK: - Cover prefetch

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

    // MARK: - Search typeahead (Home search overlay)

    /// Live suggestions for the search overlay, from the `search_all` RPC.
    var searchTracks: [HomeTrack] = []
    var searchArtists: [ExploreArtistItem] = []
    var isSearching = false
    private var searchTask: Task<Void, Never>?

    /// Debounced typeahead — runs `search_all` as the user types in the overlay.
    func runSearch(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { searchTracks = []; searchArtists = []; isSearching = false; return }

        searchTask = Task { @MainActor in
            isSearching = true
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let results = try await supabaseService.searchAll(query: q, limit: 8)
                guard !Task.isCancelled else { return }
                searchTracks = mapSearchTracks(results.tracks)
                searchArtists = mapArtists(results.artists)
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                isSearching = false
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTracks = []
        searchArtists = []
        isSearching = false
    }

    private func mapSearchTracks(_ tracks: [ApiSearchTrack]) -> [HomeTrack] {
        tracks.map { t in
            HomeTrack(
                id: t.id,
                title: t.title,
                artist: t.artist ?? "unknown",
                coverURL: storageService.resolveTrackUrl(t.coverUrl).flatMap { URL(string: $0) },
                audioURL: storageService.resolveTrackUrl(t.audioUrl).flatMap { URL(string: $0) },
                streams: t.streams,
                durationMs: t.durationMs
            )
        }
    }

    private func mapTracks(_ apiTracks: [ApiHomeTrack]?) -> [HomeTrack] {
        // cover_url / audio_url come back as bare `post-uploads` paths — resolve them.
        apiTracks?.map { track in
            HomeTrack(
                id: track.id,
                title: track.title,
                artist: track.artist ?? "unknown",
                coverURL: storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) },
                audioURL: storageService.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) },
                streams: track.streams,
                durationMs: track.durationMs
            )
        } ?? []
    }

}
