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

    /// Loads the user's saved (liked) tracks and their own uploads.
    func load(currentUserId: String?) async {
        guard case .idle = loadingState else { return }
        loadingState = .loading
        var failed = false

        do {
            savedTracks = try await supabaseService.getUserLibrary()
            prefetchCovers()
            for track in savedTracks { await mediaState?.addTrack(mediaFor(track)) }
        } catch {
            print("[LibraryVM] Failed to load saved tracks: \(error)")
            failed = true
        }

        if let currentUserId {
            do {
                uploadedTracks = try await supabaseService.getUserProfile(userId: currentUserId).tracks
                for track in uploadedTracks { await mediaState?.addTrack(mediaFor(upload: track)) }
            } catch {
                print("[LibraryVM] Failed to load uploads: \(error)")
                failed = true
            }
        }

        loadFailed = failed
        loadingState = .loaded
    }

    func refresh(currentUserId: String?) async {
        loadingState = .idle
        await load(currentUserId: currentUserId)
    }

    /// All saved tracks as `Media` (for the "See all" collection screen).
    func savedMediaList() -> [Media] {
        savedTracks.map(mediaFor)
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
            print("[LibraryVM] Failed to unsave track: \(error)")
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

    // MARK: - Uploads

    func coverURL(forUpload track: ApiProfileTrack) -> URL? {
        storageService.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }
    }

    func play(upload track: ApiProfileTrack) {
        guard let player else { return }
        let media = mediaFor(upload: track)
        Task { await mediaState?.addTrack(media) }
        player.play(media.id, of: uploadedTracks.map { MediaID($0.id) })
    }

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
}

extension LibraryScreenViewModel: PlayerStateObserving {}
