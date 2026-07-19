//
//  LibraryScreenViewModel.swift
//  Volspire
//
//

import Combine
import Foundation
import Kingfisher
import MediaLibrary
import Observation
import Player
import Services
import SharedUtilities

enum LibraryLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable @MainActor
final class LibraryScreenViewModel {
    /// How many saved tracks the Library page shows inline before "See all".
    /// Also bounds the cover prefetch so a large library doesn't warm hundreds
    /// of images for the ~10 rows actually on screen.
    let savedLimit = 10

    var playerState: MediaPlayerState = .paused(media: .none)
    var savedTracks: [ApiUserLike] = []
    var uploadedTracks: [ApiProfileTrack] = []
    var loadingState: LibraryLoadingState = .idle
    /// The last load got no response (used as an offline indicator).
    var loadFailed = false

    weak var mediaState: MediaState?
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    var cancellables = Set<AnyCancellable>()
    private let supabaseService: SupabaseService
    private let storageService: StorageService

    init(
        supabaseService: SupabaseService = SupabaseService(),
        storageService: StorageService = StorageService()
    ) {
        self.supabaseService = supabaseService
        self.storageService = storageService
    }

    /// Loads the user's saved (liked) tracks and their own uploads concurrently, so
    /// first paint waits on max(library RTT, uploads RTT) rather than their sum. Both
    /// helpers are `@MainActor`, so the state writes stay serialized and race-free.
    func load(currentUserId: String?) async {
        guard case .idle = loadingState else { return }
        loadingState = .loading

        async let savedOk = fetchSavedTracks()
        async let uploadsOk = fetchUploads(currentUserId: currentUserId)
        let (saved, uploads) = await (savedOk, uploadsOk)

        loadFailed = !saved || !uploads
        loadingState = .loaded
    }

    private func fetchSavedTracks() async -> Bool {
        do {
            let tracks = try await supabaseService.getUserLibrary()
            savedTracks = tracks
            prefetchCovers()
            for track in tracks { await mediaState?.addTrack(mediaFor(track)) }
            return true
        } catch {
            debugLog("[LibraryVM] Failed to load saved tracks: \(error)")
            return false
        }
    }

    private func fetchUploads(currentUserId: String?) async -> Bool {
        guard let currentUserId else { return true }
        do {
            let tracks = try await supabaseService.getUserProfile(userId: currentUserId).tracks
            uploadedTracks = tracks
            for track in tracks { await mediaState?.addTrack(mediaFor(upload: track)) }
            return true
        } catch {
            debugLog("[LibraryVM] Failed to load uploads: \(error)")
            return false
        }
    }

    func refresh(currentUserId: String?) async {
        loadingState = .idle
        await load(currentUserId: currentUserId)
    }

    /// All saved tracks as `Media` (for the "See all" collection screen).
    func savedMediaList() -> [Media] {
        savedTracks.map(mediaFor)
    }

    private func coverURL(forUpload track: ApiProfileTrack) -> URL? {
        storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }
    }

    /// Uploads as `Media` — registered in MediaState so an upload's ID resolves
    /// if another surface plays it.
    private func mediaFor(upload track: ApiProfileTrack) -> Media {
        Media(
            id: MediaID(track.id),
            meta: MediaMeta(
                artwork: coverURL(forUpload: track),
                title: track.title,
                artist: nil,
                audioURL: storageService.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) }
            )
        )
    }

    func play(_ track: ApiUserLike) {
        guard let player else { return }
        let media = mediaFor(track)
        Task { await mediaState?.addTrack(media) }
        let queueIDs = savedTracks.map { MediaID($0.trackId) }
        player.play(media.id, of: queueIDs)
    }

    func removeFromLibrary(_ track: ApiUserLike) async {
        do {
            try await supabaseService.unsaveTrack(trackId: track.trackId)
            savedTracks.removeAll { $0.trackId == track.trackId }
        } catch {
            debugLog("[LibraryVM] Failed to unsave track: \(error)")
        }
    }

    /// Warm the image cache for the saved-track covers so they're already decoded
    /// when the rows reveal — otherwise each cover loads + fades in mid-entrance,
    /// out of sync with the section's slide. Mirrors `ProfileScreenViewModel`.
    func prefetchCovers() {
        let urls = savedTracks.prefix(savedLimit).compactMap { coverURL(for: $0) }
        guard !urls.isEmpty else { return }
        ImagePrefetcher(urls: Array(Set(urls))).start()
    }

    /// Resolved (full public URL) cover art for a liked track.
    /// `cover_url` / `audio_url` come back as bare `post-uploads` paths.
    func coverURL(for track: ApiUserLike) -> URL? {
        storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }
    }

    private func mediaFor(_ track: ApiUserLike) -> Media {
        Media(
            id: MediaID(track.trackId),
            meta: MediaMeta(
                artwork: coverURL(for: track),
                title: track.title,
                artist: track.artist?.username,
                audioURL: storageService.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) }
            )
        )
    }

}

extension LibraryScreenViewModel: PlayerStateObserving {}
