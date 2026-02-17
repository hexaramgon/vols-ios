//
//  MediaState.swift
//  MediaLibrary
//

import Foundation

/// Protocol for managing the media library.
@MainActor
public protocol MediaState: AnyObject {
    /// All media lists (playlists/albums).
    func mediaLists() -> [MediaList]

    /// All individual tracks.
    func allTracks() -> [Media]

    /// Load library data.
    func load() async

    /// Add a track to the library.
    func addTrack(_ media: Media) async

    /// Remove a track from the library.
    func removeTrack(_ mediaID: MediaID) async

    /// Add a media list (playlist/album) to the library.
    func addMediaList(_ mediaList: MediaList) async

    /// Remove a media list from the library.
    func removeMediaList(_ mediaListID: MediaListID) async
}

public extension MediaState {
    func metaOfMedia(withID id: MediaID) -> MediaMeta? {
        media(withID: id)?.meta
    }

    func media(withID id: MediaID) -> Media? {
        allTracks().first { $0.id == id }
    }
}

public extension MediaState {
    var defaultPlayItems: (media: MediaID, items: [MediaID])? {
        let lists = mediaLists().filter { !$0.items.isEmpty }
        guard let list = lists.randomElement(),
              let item = list.items.randomElement()
        else { return nil }
        return (item.id, list.items.map(\.id))
    }
}
