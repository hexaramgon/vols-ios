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

/// A home rail/feed track row, mapped at ingest (URLs resolved once).
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

/// Screen-local state for Home: playback dispatch, the pull-refresh chip,
/// the create-folder form, and the search typeahead. All server content lives
/// in the shared stores (FeedStore / WorkspaceStore / ListingsStore /
/// SocialStore) — this object mostly composes them.
@Observable
@MainActor
class HomeScreenViewModel {
    // Create-folder sheet on the Workspace tab. The folders themselves live in
    // the shared WorkspaceStore; only the form state is screen-local.
    var showCreateFolder = false
    var newFolderName = ""
    var newFolderDescription = ""
    var isCreatingFolder = false

    /// Shared stores — assigned by HomeScreen's `.task`.
    weak var feed: FeedStore?
    weak var workspace: WorkspaceStore?
    /// Search-result artist rows seed the follow overlay.
    weak var social: SocialStore?
    weak var listingsStore: ListingsStore?

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

    /// First load — the feed rails and the collab listings warm concurrently
    /// (both stores' loads are guarded, so later tab opens are no-ops).
    func loadInitial() async {
        async let feedDone: Void = warmFeed()
        async let listingsDone: Void = warmListings()
        _ = await (feedDone, listingsDone)
    }

    private func warmFeed() async {
        await feed?.loadInitial()
    }

    private func warmListings() async {
        await listingsStore?.loadListingsIfNeeded()
    }

    // MARK: - Pull-to-refresh (chip-wrapped store delegates)

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
        // The All tab also shows the Collab rail, so refresh listings with it.
        async let feedDone: Void = refreshFeedAll()
        async let listingsDone: Void = refreshListingsQuiet()
        _ = await (feedDone, listingsDone)
    }

    private func refreshFeedAll() async {
        await feed?.refreshAll()
    }

    private func refreshListingsQuiet() async {
        await listingsStore?.refreshListings()
    }

    func refreshFollowing() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await feed?.refreshFollowing()
    }

    func refreshArtists() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await feed?.refreshArtists()
    }

    func refreshListings() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await listingsStore?.refreshListings()
    }

    /// Pull-to-refresh for the Saved list, chip-wrapped like the board's.
    func refreshSavedListings() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        await listingsStore?.refreshSaved()
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
                searchArtists = mapSearchArtists(results.artists)
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

    /// Search-scoped artist mapping (the rails' mapping lives in FeedStore).
    private func mapSearchArtists(_ items: [ApiExploreArtist]) -> [ExploreArtistItem] {
        items.map {
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
}
