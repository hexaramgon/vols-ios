//
//  MediaState.swift
//  MediaLibrary
//

import Foundation

/// Protocol for managing the media library.
@MainActor
public protocol MediaState: AnyObject {
    /// All individual tracks.
    func allTracks() -> [Media]

    /// A single track by id. Conformers backed by an id-keyed store should
    /// override this for an O(1) lookup; the default scans `allTracks()`.
    func media(withID id: MediaID) -> Media?

    /// Add a track to the library.
    func addTrack(_ media: Media) async

    /// Remove a track from the library.
    func removeTrack(_ mediaID: MediaID) async

    /// Wipe everything (sign-out teardown).
    func removeAll() async
}

public extension MediaState {
    func metaOfMedia(withID id: MediaID) -> MediaMeta? {
        media(withID: id)?.meta
    }

    func media(withID id: MediaID) -> Media? {
        allTracks().first { $0.id == id }
    }
}
