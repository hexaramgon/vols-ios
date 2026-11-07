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

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
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

    // MARK: - Pull-to-refresh (store delegates, wrapped in the chip)

    /// True while any pull-to-refresh is running — the screen floats its own
    /// indicator below the fixed header off this flag.
    var isPullRefreshing = false
    private var pullRefreshCount = 0 {
        didSet { isPullRefreshing = pullRefreshCount > 0 }
    }

    /// Runs a user-initiated refresh behind the chip, holding it up at least
    /// ~0.6s — a fast refresh otherwise flashed it for a frame and read as
    /// "nothing happened".
    func withRefreshChip(_ work: () async -> Void) async {
        pullRefreshCount += 1
        let start = ContinuousClock.now
        await work()
        let minimum = Duration.milliseconds(600)
        let elapsed = ContinuousClock.now - start
        if elapsed < minimum { try? await Task.sleep(for: minimum - elapsed) }
        pullRefreshCount -= 1
    }

    /// Collab: charts, artists, map, plus the listings preview the Collab
    /// tab shows.
    func refreshCollab() async {
        async let feedDone: Void = refreshFeedAll()
        async let listingsDone: Void = refreshListingsQuiet()
        _ = await (feedDone, listingsDone)
    }

    private func refreshFeedAll() async { await feed?.refreshAll() }
    private func refreshListingsQuiet() async { await listingsStore?.refreshListings() }

    func refreshFollowing() async {
        async let feedDone: Void = refreshFollowingFeed()
        async let foldersDone: Void = refreshFoldersQuiet()
        _ = await (feedDone, foldersDone)
    }

    private func refreshFollowingFeed() async { await feed?.refreshFollowing() }
    private func refreshFoldersQuiet() async { await workspace?.refreshFolders() }

    func refreshListings() async {
        async let board: Void = refreshListingsQuiet()
        async let saved: Void = refreshSavedQuiet()
        _ = await (board, saved)
    }

    private func refreshSavedQuiet() async { await listingsStore?.refreshSaved() }
}
