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
struct WorkspaceActivityGroup: Identifiable {
    let actorId: String
    let username: String?
    let avatar: String?
    /// Newest first.
    let events: [ApiWorkspaceActivity]
    var id: String { actorId }
}

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

// MARK: - Loading State

enum HomeLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - ViewModel

@Observable
@MainActor
class HomeScreenViewModel {
    var loadingState: HomeLoadingState = .idle
    var errorMessage: String?

    // Sections — mirror the web app's home buckets (`get_home_tracks`).
    var popularTracks: [HomeTrack] = []
    var demos: [HomeTrack] = []
    var samples: [HomeTrack] = []

    // Explore tab data (lazy-loaded the first time each tab is opened).
    var feedTracks: [HomeTrack] = []
    var followingTracks: [HomeTrack] = []
    var artists: [ExploreArtistItem] = []
    var folders: [ApiUserFolder] = []
    /// Collaborators' actions across shared folders in the past month
    /// (Workspace tab rail), newest first.
    var workspaceActivity: [ApiWorkspaceActivity] = []

    /// Activity grouped per collaborator (stories-style rail): one entry per
    /// person, ordered by their most recent action, events newest-first.
    var activityGroups: [WorkspaceActivityGroup] {
        var order: [String] = []
        var byActor: [String: [ApiWorkspaceActivity]] = [:]
        for event in workspaceActivity {
            if byActor[event.actorId] == nil { order.append(event.actorId) }
            byActor[event.actorId, default: []].append(event)
        }
        return order.map { actorId in
            let events = byActor[actorId] ?? []
            return WorkspaceActivityGroup(
                actorId: actorId,
                username: events.first?.actorUsername,
                avatar: events.first?.actorAvatar,
                events: events
            )
        }
    }
    var feedLoaded = false
    var followingLoaded = false
    var artistsLoaded = false
    var foldersLoaded = false

    // Collab listings (lazy-loaded the first time the Collab tab opens).
    var collabListings: [ApiListing] = []
    var listingsLoaded = false

    /// Random shuffle seed for the explore feed (`get_home_feed`). Fresh per VM
    /// (i.e. per app session) and re-rolled on pull-to-refresh, so the recs vary
    /// instead of returning the same order every time — matching the web.
    private var feedSeed = Int.random(in: 1 ... 1_000_000)

    /// Top popular tracks shown in the Featured carousel.
    var featuredTracks: [HomeTrack] { Array(popularTracks.prefix(5)) }

    weak var mediaState: MediaState?
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

    /// Play a track from the home screen by adding it to the media library and starting playback.
    /// Plays `track` and queues the rest of the section it came from (`context`)
    /// in its natural order, so Next/Previous move through *that* section — not a
    /// concatenation of every home rail (which is why Next used to jump to the
    /// top "Popular" tracks).
    func playTrack(_ track: HomeTrack, in context: [HomeTrack]) async {
        guard track.audioURL != nil else { return }

        // Queue = the section in order. The tapped track must be in it (it is,
        // since it came from that list) or `MediaPlayer.play` rejects the queue.
        var ordered = context
        if !ordered.contains(where: { $0.id == track.id }) { ordered = [track] }

        var seen = Set<String>()
        let queue = ordered.filter { $0.audioURL != nil && seen.insert($0.id).inserted }

        for t in queue {
            await mediaState?.addTrack(
                Media(
                    id: MediaID(t.id),
                    meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL)
                )
            )
        }

        player?.play(MediaID(track.id), of: queue.map { MediaID($0.id) })
    }

    /// Load home data from Supabase
    func loadHomeData() async {
        guard loadingState != .loading else { return }

        loadingState = .loading
        errorMessage = nil

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
            errorMessage = error.localizedDescription
        }
    }

    /// First load — every section fetches concurrently instead of waterfalling.
    func loadInitial() async {
        async let home: Void = loadHomeData()
        async let artistRail: Void = loadArtists()
        async let feed: Void = loadTracksFeed()
        // Collab listings also feed the "All" tab's Collab rail (not just the
        // Collab tab), so warm them on first load — `loadListings` is guarded, so
        // opening the Collab tab afterwards is a no-op.
        async let listings: Void = loadListings()
        _ = await (home, artistRail, feed, listings)
    }

    func refresh() async {
        loadingState = .idle
        feedLoaded = false
        feedSeed = Int.random(in: 1 ... 1_000_000) // fresh shuffle on pull-to-refresh
        async let home: Void = loadHomeData()
        async let feed: Void = loadTracksFeed()
        _ = await (home, feed)
    }

    // MARK: - Explore tabs

    func loadTracksFeed() async {
        guard !feedLoaded else { return }
        feedLoaded = true
        do { feedTracks = mapTracks(try await supabaseService.getExploreTracksFeed(seed: feedSeed)); prefetchCovers(feedTracks) }
        catch { feedLoaded = false; print("[HomeVM] tracks feed: \(error)") }
    }

    func loadFollowing() async {
        guard !followingLoaded else { return }
        followingLoaded = true
        do { followingTracks = mapTracks(try await supabaseService.getFollowingFeed()); prefetchCovers(followingTracks) }
        catch { followingLoaded = false; print("[HomeVM] following: \(error)") }
    }

    func loadFolders() async {
        guard !foldersLoaded else { return }
        foldersLoaded = true
        // Generous limit: the RPC is already scoped to the past month and the
        // rail groups client-side, so fetch the whole window.
        async let activity = supabaseService.getWorkspaceActivity(limit: 100)
        do { folders = try await supabaseService.getUserFolders() }
        catch { print("[HomeVM] loadFolders: \(error)") }
        workspaceActivity = (try? await activity) ?? []
    }

    /// Resolves an activity actor's avatar (bare storage path or full URL).
    func activityAvatarURL(_ pathOrUrl: String?) -> URL? {
        storageService.avatarUrl(pathOrUrl: pathOrUrl).flatMap { URL(string: $0) }
    }

    func loadArtists() async {
        guard !artistsLoaded else { return }
        artistsLoaded = true
        do {
            artists = try await supabaseService.getExploreArtists().map {
                ExploreArtistItem(
                    id: $0.userId,
                    username: $0.username ?? "unknown",
                    avatarURL: $0.profileImageUrl.flatMap { URL(string: $0) },
                    monthlyListeners: $0.monthlyListeners ?? 0,
                    isFollowing: $0.isFollowing ?? false
                )
            }
            prefetchArtistAvatars(artists)
        } catch { artistsLoaded = false; print("[HomeVM] artists: \(error)") }
    }

    func loadListings() async {
        guard !listingsLoaded else { return }
        listingsLoaded = true
        do { collabListings = try await supabaseService.getListings(category: nil) }
        catch { listingsLoaded = false; print("[HomeVM] listings: \(error)") }
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

    func toggleFollow(_ item: ExploreArtistItem) async {
        guard let idx = artists.firstIndex(where: { $0.id == item.id }) else { return }
        artists[idx].isFollowing.toggle()
        do { try await supabaseService.toggleFollow(targetUser: item.id) }
        catch { artists[idx].isFollowing.toggle() }
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
                searchArtists = results.artists.map {
                    ExploreArtistItem(
                        id: $0.userId,
                        username: $0.username ?? "unknown",
                        avatarURL: $0.profileImageUrl.flatMap { URL(string: $0) },
                        monthlyListeners: $0.monthlyListeners ?? 0,
                        isFollowing: $0.isFollowing ?? false
                    )
                }
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
