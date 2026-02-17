//
//  DefaultMediaState.swift
//  MediaLibrary
//

import Foundation
import Observation

/// Observable media state that holds tracks and playlists.
@Observable @MainActor
public final class DefaultMediaState: MediaState {
    public var tracks: [MediaID: Media] = [:]
    public var lists: [MediaListID: MediaList] = [:]

    public init() {}

    // MARK: - MediaState

    public func mediaLists() -> [MediaList] {
        Array(lists.values)
    }

    public func allTracks() -> [Media] {
        Array(tracks.values)
    }

    public func load() async {
        // Override to load from a data source
    }

    public func addTrack(_ media: Media) async {
        tracks[media.id] = media
    }

    public func removeTrack(_ mediaID: MediaID) async {
        tracks.removeValue(forKey: mediaID)
    }

    public func addMediaList(_ mediaList: MediaList) async {
        lists[mediaList.id] = mediaList
        // Also add individual tracks
        for item in mediaList.items {
            tracks[item.id] = item
        }
    }

    public func removeMediaList(_ mediaListID: MediaListID) async {
        lists.removeValue(forKey: mediaListID)
    }
}
