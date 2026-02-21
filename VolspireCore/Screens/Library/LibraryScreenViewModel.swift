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

@Observable @MainActor
final class LibraryScreenViewModel {
    var playerState: MediaPlayerState = .paused(media: .none)
    var playIndicatorSpectrum: [Float] = .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)

    weak var mediaState: MediaState?
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    var cancellables = Set<AnyCancellable>()

    var allSongs: [Media] {
        guard let mediaState else { return [] }
        return mediaState.allTracks()
    }

    func play(_ track: Media) {
        guard let player else { return }
        player.play(track.id, of: allSongs.map(\.id))
    }
}

extension LibraryScreenViewModel: PlayerStateObserving {}
