//
//  MediaItemScreenViewModel.swift
//  Volspire
//
//

import Combine
import MediaLibrary
import Observation
import Player
import SwiftUI

@Observable @MainActor
class MediaItemScreenViewModel {
    let item: Media

    weak var mediaState: MediaState?
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    var playerState: MediaPlayerState = .paused(media: .none)
    var playIndicatorSpectrum: [Float] = .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
    var cancellables = Set<AnyCancellable>()

    init(item: Media) {
        self.item = item
    }

    func onSelect(media: MediaID) {
        guard let player else { return }
        player.play(media, of: [item.id])
    }

    func onPlay() {
        guard let player else { return }
        player.play(item.id, of: [item.id])
    }
}

extension MediaItemScreenViewModel: PlayerStateObserving {}
