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

/// Playback adapter for the Library page. All library CONTENT (saved tracks,
/// uploads, playlists) lives in the shared `LibraryStore`; this keeps only the
/// player mirroring that drives the rows' playing indicator.
@Observable @MainActor
final class LibraryScreenViewModel {
    var playerState: MediaPlayerState = .paused(media: .none)
    var cancellables = Set<AnyCancellable>()

    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    /// Plays a saved track with the whole saved list queued behind it — the
    /// shared queue-and-play helper registers the queue in MediaState first.
    func play(_ track: ApiUserLike, queue: [Media]) {
        guard let player else { return }
        Task { await player.play(MediaID(track.trackId), queue: queue) }
    }
}

extension LibraryScreenViewModel: PlayerStateObserving {}
