//
//  LibraryScreenViewModel.swift
//  Volspire
//
//

import Foundation
import MediaLibrary
import Observation
import Player
import Services

/// Playback adapter for the Library page. All CONTENT (saved tracks,
/// playlists, the Short tracks / Snippets / Fresh feeds) lives in the shared
/// `LibraryStore` / `FeedStore`; this only starts playback with the right queue.
@Observable @MainActor
final class LibraryScreenViewModel {
    weak var player: MediaPlayer?

    /// Plays `track` and queues the section it came from (`context`) in its
    /// natural order, so Next/Previous move through *that* list.
    func playTrack(_ track: HomeTrack, in context: [HomeTrack]) async {
        guard track.audioURL != nil else { return }
        var ordered = context
        if !ordered.contains(where: { $0.id == track.id }) { ordered = [track] }
        await player?.play(MediaID(track.id), queue: ordered.map { t in
            Media(
                id: MediaID(t.id),
                meta: MediaMeta(artwork: t.coverURL, title: t.title, artist: t.artist, audioURL: t.audioURL)
            )
        })
    }
}
