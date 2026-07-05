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

    weak var mediaState: MediaState?
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
    func play(_ track: ApiSearchTrack) async {
        guard let audio = storageService.resolveTrackUrl(track.audioUrl).flatMap({ URL(string: $0) }) else { return }

        // The tapped track must be in the queue or `MediaPlayer.play` rejects it.
        var seen = Set<String>()
        let queue = tracks.filter { seen.insert($0.id).inserted && ($0.id == track.id || $0.audioUrl != nil) }

        for t in queue {
            let url = t.id == track.id ? audio : storageService.resolveTrackUrl(t.audioUrl).flatMap { URL(string: $0) }
            await mediaState?.addTrack(
                Media(
                    id: MediaID(t.id),
                    meta: MediaMeta(
                        artwork: cover(t.coverUrl),
                        title: t.title,
                        artist: t.artist ?? "unknown",
                        audioURL: url
                    )
                )
            )
        }
        player?.play(MediaID(track.id), of: queue.map { MediaID($0.id) })
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
        searchTask = Task { @MainActor in
            isLoading = true
            // Debounce so we don't fire an RPC on every keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let results = try await supabaseService.searchAll(query: query)
                guard !Task.isCancelled else { return }
                tracks = results.tracks
                artists = results.artists
                packs = results.packs
                services = results.services
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
