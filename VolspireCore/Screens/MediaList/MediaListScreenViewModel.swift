//
//  MediaListScreenViewModel.swift
//  Volspire
//
//

import Combine
import MediaLibrary
import Observation
import Player
import SwiftUI

@Observable @MainActor
class MediaListScreenViewModel {
    weak var mediaState: MediaState?
    let items: [Media]
    let listMeta: MediaList.Meta?
    var playerState: MediaPlayerState = .paused(media: .none)
    var playIndicatorSpectrum: [Float] = .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
    var cancellables = Set<AnyCancellable>()

    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    init(items: [Media], listMeta: MediaList.Meta?) {
        self.items = items
        self.listMeta = listMeta
    }

    func onSelect(media: MediaID) {
        guard let player else { return }
        player.play(media, of: items.map(\.id))
    }

    func onPlay() {
        guard let player, let item = items.first else { return }
        player.play(item.id, of: items.map(\.id))
    }

    func onShuffle() {
        guard let player, !items.isEmpty else { return }
        let shuffledItems = items.map(\.id).shuffled()
        guard let itemID = shuffledItems.first else { return }

        player.play(itemID, of: shuffledItems)
    }

    func swipeButtons(mediaID: MediaID) -> [MediaListSwipeButton] {
        [.delete]
    }

    func onSwipeActions(mediaID: MediaID, button: MediaListSwipeButton) {
        Task {
            switch button {
            case .delete:
                await mediaState?.removeTrack(mediaID)
            case .download:
                break
            }
        }
    }

    var footer: LocalizedStringKey {
        "^[\(items.count) track](inflect: true)"
    }
}

extension MediaListScreenViewModel: PlayerStateObserving {}
