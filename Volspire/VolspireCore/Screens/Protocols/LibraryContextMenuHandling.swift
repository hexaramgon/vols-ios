//
//  LibraryContextMenuHandling.swift
//  Volspire
//

import Foundation
import MediaLibrary
import Player

@MainActor
protocol LibraryContextMenuHandling: AnyObject {
    var mediaState: MediaState? { get }
    var player: MediaPlayer? { get }
}

extension LibraryContextMenuHandling {
    func contextMenu(for item: MediaItem) -> [LibraryContextMenuItem?] {
        [.play, nil, .delete]
    }

    func onSelect(_ menuItem: LibraryContextMenuItem, of item: MediaItem) {
        switch menuItem {
        case .play:
            play(item)
        case .download:
            break
        case .delete:
            delete(item)
        }
    }

    func play(_ item: MediaItem) {
        switch item {
        case let .mediaItem(media):
            player?.play(media.id, of: [media.id])
        case let .mediaList(mediaList):
            if let media = mediaList.items.first {
                player?.play(media.id, of: mediaList.items.map(\.id))
            }
        }
    }

    func delete(_ item: MediaItem) {
        guard let mediaState else { return }
        Task {
            switch item {
            case let .mediaItem(media):
                await mediaState.removeTrack(media.id)
            case let .mediaList(mediaList):
                await mediaState.removeMediaList(mediaList.id)
            }
        }
    }
}
