//
//  AudioEffects.swift
//  Player
//
//  Model for audio effects: playback speed and whether pitch is preserved.
//

import Foundation

/// Represents the current audio effect settings.
///
/// Mirrors the web app's player: a single **speed** control plus a
/// **preserve pitch** toggle. When pitch is preserved, changing speed alters
/// tempo only; when not, speed also shifts pitch (tape/varispeed style).
public struct AudioEffects: Equatable, Sendable {
    /// Playback speed multiplier (0.25x – 2.0x). Default is 1.0.
    public var speed: Float

    /// When `true`, speed changes tempo only (pitch held constant).
    /// When `false`, speed also changes pitch (varispeed). Default is `false`.
    public var preservePitch: Bool

    public init(speed: Float, preservePitch: Bool) {
        self.speed = speed
        self.preservePitch = preservePitch
    }

    public static let `default` = AudioEffects(
        speed: 1.0,
        preservePitch: false
    )
}
