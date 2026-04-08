//
//  LibraryScreenViewModel.swift
//  Volspire
//
//

import Combine
import Foundation
import MediaLibrary
import Observation
import Player
import Services

enum LibraryLoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

@Observable @MainActor
final class LibraryScreenViewModel {
    var playerState: MediaPlayerState = .paused(media: .none)
    var playIndicatorSpectrum: [Float] = .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
    var likedTracks: [ApiUserLike] = []
    var loadingState: LibraryLoadingState = .idle

    weak var mediaState: MediaState?
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    var cancellables = Set<AnyCancellable>()
    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
    }

    func loadLikes() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading

        do {
            likedTracks = try await supabaseService.getUserLikes()
            // Register tracks in media state so the player can resolve them
            for track in likedTracks {
                let media = mediaFor(track)
                await mediaState?.addTrack(media)
            }
            loadingState = .loaded
        } catch {
            print("[LibraryVM] Failed to load likes: \(error)")
            loadingState = .error(error.localizedDescription)
        }
    }

    func refreshLikes() async {
        loadingState = .idle
        await loadLikes()
    }

    func play(_ track: ApiUserLike) {
        guard let player else { return }
        let media = mediaFor(track)
        Task { await mediaState?.addTrack(media) }
        let queueIDs = likedTracks.map { MediaID($0.trackId) }
        player.play(media.id, of: queueIDs)
    }

    func removeFromLibrary(_ track: ApiUserLike) async {
        do {
            try await supabaseService.removeTrackLike(trackId: track.trackId)
            likedTracks.removeAll { $0.trackId == track.trackId }
        } catch {
            print("[LibraryVM] Failed to remove like: \(error)")
        }
    }

    private func mediaFor(_ track: ApiUserLike) -> Media {
        Media(
            id: MediaID(track.trackId),
            meta: MediaMeta(
                artwork: track.coverUrl.flatMap { URL(string: $0) },
                title: track.title,
                artist: track.artist?.username,
                audioURL: track.audioUrl.flatMap { URL(string: $0) }
            )
        )
    }
}

extension LibraryScreenViewModel: PlayerStateObserving {}
