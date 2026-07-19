//
//  DefaultMediaState.swift
//  MediaLibrary
//

import Foundation
import Observation

/// Observable media state that holds tracks.
@Observable @MainActor
public final class DefaultMediaState: MediaState {
    public var tracks: [MediaID: Media] = [:]

    public init() {}

    // MARK: - MediaState

    public func allTracks() -> [Media] {
        Array(tracks.values)
    }

    /// O(1) override of the protocol default (which scans `allTracks()`).
    public func media(withID id: MediaID) -> Media? {
        tracks[id]
    }

    public func addTrack(_ media: Media) async {
        tracks[media.id] = media
    }

    public func removeTrack(_ mediaID: MediaID) async {
        tracks.removeValue(forKey: mediaID)
    }

    public func removeAll() async {
        tracks.removeAll()
    }
}
