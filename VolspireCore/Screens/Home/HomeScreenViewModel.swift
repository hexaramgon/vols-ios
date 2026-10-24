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

/// Who a Collab pitch goes to (the web's `PitchTarget`).
struct PitchTarget: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: URL?
}

// MARK: - ViewModel

/// Screen-local state for Home: playback dispatch (and the queue it started,
/// for the Now playing panel), the pull-refresh chip, the create-folder form,
/// and the search typeahead. All server content lives in the shared stores
/// (FeedStore / WorkspaceStore / ListingsStore / SocialStore / LibraryStore).
@Observable
@MainActor
class HomeScreenViewModel {
    /// Shared stores — assigned by HomeScreen's `.task`.
    weak var feed: FeedStore?
    weak var workspace: WorkspaceStore?
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

    /// Plays `track` and queues the section it came from (`context`) in its
    /// natural order, so Next/Previous move through *that* list.
    func playTrack(_ track: HomeTrack, in context: [HomeTrack]) async {
        guard track.audioURL != nil else { return }
        var ordered = context
        if !ordered.contains(where: { $0.id == track.id }) { ordered = [track] }
        await player?.play(MediaID(track.id), queue: ordered.map { t in
            Media(
                id: MediaID(t.id),
                meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL)
            )
        })
    }

    /// First load — the charts/artists and the listings board warm concurrently.
    func loadInitial() async {
        async let feedDone: Void = warmFeed()
        async let listingsDone: Void = warmListings()
        _ = await (feedDone, listingsDone)
    }

    private func warmFeed() async { await feed?.loadInitial() }
    private func warmListings() async { await listingsStore?.loadListingsIfNeeded() }

    // MARK: - Pull-to-refresh (chip-wrapped store delegates)

    /// True while any pull-to-refresh is running — the screen floats its own
    /// indicator below the fixed header off this flag.
    var isPullRefreshing = false
    private var pullRefreshCount = 0 {
        didSet { isPullRefreshing = pullRefreshCount > 0 }
    }

    /// Collab: charts, artists, map, plus the listings
    /// preview the Collab tab shows.
    func refresh() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        async let feedDone: Void = refreshFeedAll()
        async let listingsDone: Void = refreshListingsQuiet()
        _ = await (feedDone, listingsDone)
    }

    private func refreshFeedAll() async { await feed?.refreshAll() }
    private func refreshListingsQuiet() async { await listingsStore?.refreshListings() }

    func refreshFollowing() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        async let feedDone: Void = refreshFollowingFeed()
        async let foldersDone: Void = refreshFoldersQuiet()
        _ = await (feedDone, foldersDone)
    }

    private func refreshFollowingFeed() async { await feed?.refreshFollowing() }
    private func refreshFoldersQuiet() async { await workspace?.refreshFolders() }

    func refreshListings() async {
        pullRefreshCount += 1
        defer { pullRefreshCount -= 1 }
        async let board: Void = refreshListingsQuiet()
        async let saved: Void = refreshSavedQuiet()
        _ = await (board, saved)
    }

    private func refreshSavedQuiet() async { await listingsStore?.refreshSaved() }



    // MARK: - Search typeahead (Home search sheet)

    /// One suggestion row (web `Suggestion`): a track title or an artist.
    enum Suggestion: Identifiable, Hashable {
        case track(HomeTrack)
        case artist(ExploreArtistItem)
        var id: String {
            switch self {
            case .track(let t): "t-\(t.id)"
            case .artist(let a): "a-\(a.id)"
            }
        }
    }

    /// Up to 6 rows: 3 title/artist prefix matches, 3 artists, then 2
    /// contains-matches (the web's ordering).
    private(set) var suggestions: [Suggestion] = []
    private(set) var isSearching = false
    /// The query `suggestions` answer — set only on a successful response, so
    /// the overlay shows bones (not "No results") while in flight or failed.
    private(set) var suggestionsQuery: String?
    private var searchTask: Task<Void, Never>?

    /// Debounced typeahead — runs `search_all` as the user types.
    func runSearch(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { suggestions = []; suggestionsQuery = nil; isSearching = false; return }

        searchTask = Task { @MainActor in
            isSearching = true
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let results = try await supabaseService.searchAll(query: q, limit: 8)
                guard !Task.isCancelled else { return }
                suggestions = buildSuggestions(q, tracks: mapSearchTracks(results.tracks),
                                               artists: feed?.mapArtists(results.artists) ?? [])
                suggestionsQuery = q
            } catch {
                guard !Task.isCancelled else { return }
            }
            isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        suggestions = []
        suggestionsQuery = nil
        isSearching = false
    }

    private func buildSuggestions(_ q: String, tracks: [HomeTrack], artists: [ExploreArtistItem]) -> [Suggestion] {
        let lq = q.lowercased()
        let prefix = tracks.filter { $0.title.lowercased().hasPrefix(lq) || $0.artist.lowercased().hasPrefix(lq) }
        let prefixIds = Set(prefix.map(\.id))
        let contains = tracks.filter { !prefixIds.contains($0.id) }
        let rows: [Suggestion] = prefix.prefix(3).map { .track($0) }
            + artists.prefix(3).map { .artist($0) }
            + contains.prefix(2).map { .track($0) }
        return Array(rows.prefix(6))
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
}
