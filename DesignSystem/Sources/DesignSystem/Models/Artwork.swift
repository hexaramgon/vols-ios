//
//  Artwork.swift
//  Volspire
//
//

import AVFoundation
import Foundation

public enum Artwork: Hashable {
    case placeholder(name: String? = nil)
    case album
    case webImage(URL)
    case videoPlayer(AVPlayer)

    public static func == (lhs: Artwork, rhs: Artwork) -> Bool {
        switch (lhs, rhs) {
        case let (.placeholder(a), .placeholder(b)): a == b
        case (.album, .album): true
        case let (.webImage(a), .webImage(b)): a == b
        case let (.videoPlayer(a), .videoPlayer(b)): a === b
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .placeholder(name):
            hasher.combine(0)
            hasher.combine(name)
        case .album:
            hasher.combine(1)
        case let .webImage(url):
            hasher.combine(2)
            hasher.combine(url)
        case let .videoPlayer(player):
            hasher.combine(3)
            hasher.combine(ObjectIdentifier(player))
        }
    }
}

public extension Artwork {
    static func placeholder(
        _ url: URL?,
        name: String? = nil
    ) -> Artwork {
        url.map { .webImage($0) } ?? .placeholder(name: name)
    }

    static func album(_ url: URL?) -> Artwork {
        url.map { .webImage($0) } ?? .album
    }

    static func placeholderImage(
        _ urlString: String?,
        name: String? = nil
    ) -> Artwork {
        .placeholder(
            urlString.flatMap { URL(string: $0) },
            name: name
        )
    }
}
