//
//  MediaState+Stub.swift
//  MediaLibrary
//

import Foundation

public extension DefaultMediaState {
    static var stub: DefaultMediaState = {
        let state = DefaultMediaState()
        // Add some sample data for previews
        let sampleTracks = [
            Media(
                id: MediaID("sample-1"),
                meta: MediaMeta(
                    artwork: nil,
                    title: "Sample Track 1",
                    artist: "Artist 1",
                    genre: "Pop"
                )
            ),
            Media(
                id: MediaID("sample-2"),
                meta: MediaMeta(
                    artwork: nil,
                    title: "Sample Track 2",
                    artist: "Artist 2",
                    genre: "Rock"
                )
            ),
        ]

        let sampleList = MediaList(
            id: MediaListID("sample-playlist"),
            meta: .init(
                artwork: nil,
                title: "Sample Playlist",
                subtitle: "Preview Data"
            ),
            items: sampleTracks
        )

        state.lists[sampleList.id] = sampleList
        for track in sampleTracks {
            state.tracks[track.id] = track
        }

        return state
    }()
}
