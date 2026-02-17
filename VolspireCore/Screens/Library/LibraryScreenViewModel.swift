//
//  LibraryScreenViewModel.swift
//  Volspire
//
//

import MediaLibrary
import Observation
import Player

@Observable @MainActor
final class LibraryScreenViewModel {
    weak var mediaState: MediaState?
    weak var player: MediaPlayer?

    var recentlyAdded: [MediaItem] {
        guard let mediaState else { return [] }
        let lists = mediaState.mediaLists()
        let tracks = mediaState.allTracks()

        let listItems = lists.map { MediaItem.mediaList($0) }
        let trackItems = tracks.map { MediaItem.mediaItem($0) }

        let result = (listItems + trackItems)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(20)
        return Array(result)
    }
}

extension LibraryScreenViewModel: LibraryContextMenuHandling {}
