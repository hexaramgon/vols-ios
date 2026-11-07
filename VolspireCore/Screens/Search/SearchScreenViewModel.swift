//
//  SearchScreenViewModel.swift
//  Volspire
//
//  Full-catalog search backed by the `search_all` RPC (same one the web app
//  hits via /api/search). Returns tracks, artists, packs and services for a
//  query; results are debounced per keystroke.
//

import Combine
import DesignSystem
import Foundation
import MediaLibrary
import Player
import Services
import SwiftUI

@Observable @MainActor
final class SearchScreenViewModel {
    var playerState: MediaPlayerState = .paused(media: .none)
    var isLoading = false
    var errorMessage: String?

    // Result groups (mirror the web's SearchData buckets).
    var tracks: [ApiSearchTrack] = []
    var artists: [ApiExploreArtist] = []
    var packs: [ApiMarketplacePack] = []
    var services: [ApiMarketplaceService] = []

    weak var player: MediaPlayer? {
        didSet { observeMediaPlayerState() }
    }

    var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    private let supabaseService: SupabaseService
    private let storageService: StorageService

    init(
        supabaseService: SupabaseService = SupabaseService(),
        storageService: StorageService = StorageService()
    ) {
        self.supabaseService = supabaseService
        self.storageService = storageService
    }

    var searchText: String = "" {
        didSet { if searchText != oldValue { performSearch() } }
    }

    var hasResults: Bool {
        !tracks.isEmpty || !artists.isEmpty || !packs.isEmpty || !services.isEmpty
    }

    /// Re-run the current query (used by the error state's Try Again).
    func retry() { performSearch() }

    /// Resolves a bare `post-uploads` cover path to a public URL (packs/services).
    func cover(_ path: String?) -> URL? {
        storageService.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }

    func coverURL(for track: ApiSearchTrack) -> URL? { cover(track.coverUrl) }

    /// Plays a search track, queueing the rest of the track results behind it.
    /// The shared queue-and-play helper registers the queue in MediaState,
    /// dedupes by id, and drops rows with no audio.
    func play(_ track: ApiSearchTrack) async {
        guard let player,
              storageService.trackMediaURL(track.audioUrl) != nil else { return }

        let queue = tracks.map { t in
            Media(
                id: MediaID(t.id),
                meta: MediaMeta(
                    artwork: cover(t.coverUrl),
                    title: t.title,
                    artist: t.artist ?? "unknown",
                    audioURL: storageService.trackMediaURL(t.audioUrl)
                )
            )
        }
        await player.play(MediaID(track.id), queue: queue)
    }
}

private extension SearchScreenViewModel {
    func performSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearResults()
            errorMessage = nil
            isLoading = false
            return
        }

        errorMessage = nil
        // Flip to loading NOW, not inside the task: the gap before the task's
        // first turn rendered "No results" for a query that hadn't run yet.
        isLoading = true
        searchTask = Task { @MainActor in
            // Debounce so we don't fire an RPC on every keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let results = try await supabaseService.searchAll(query: query)
                guard !Task.isCancelled else { return }
                tracks = results.tracks
                artists = results.artists
                // Dropped while monetization is off (FeatureFlags.marketplace):
                // pack/service detail pages show a price with nothing to buy and
                // carry no report/block affordance, so they must not be
                // reachable. Gating here rather than at the two section views
                // keeps `hasResults` and the analytics count honest — hiding
                // only the sections would leave a pack-only query claiming
                // results while rendering an empty list.
                // The free-packs slice returns free packs (with report /
                // block on their pages) and still no services.
                packs = FeatureFlags.marketplace ? results.packs
                    : FeatureFlags.freePacks ? results.packs.filter { ($0.price ?? 0) <= 0 } : []
                services = FeatureFlags.marketplace ? results.services : []
                isLoading = false
                AnalyticsService.shared?.log(.searchPerformed, metadata: [
                    "query": .string(query),
                    "results": .int(tracks.count + artists.count + packs.count + services.count),
                ])
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                clearResults()
                isLoading = false
            }
        }
    }

    func clearResults() {
        tracks = []
        artists = []
        packs = []
        services = []
    }
}

extension SearchScreenViewModel: PlayerStateObserving {}
