//
//  MediaPlaybackMode.swift
//  MediaLibrary
//

/// A playback mode option (e.g. shuffle, repeat).
public struct MediaPlaybackMode: Identifiable {
    public struct ID: Hashable {
        public let value: String

        public init(value: String) {
            self.value = value
        }
    }

    public let id: ID
    public let title: String

    public init(id: ID, title: String) {
        self.id = id
        self.title = title
    }
}
