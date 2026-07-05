//
//  PlayerController+Stub.swift
//  Volspire
//
//

import Foundation

extension PlayerController {
    static var stub: PlayerController {
        let result = PlayerController()
        result.display = .init(
            artwork: .placeholder(name: "Sample Track"),
            albumArtwork: .placeholder(name: "Sample Track"),
            title: "Sample Track",
            subtitle: "Sample Artist"
        )
        return result
    }
}
