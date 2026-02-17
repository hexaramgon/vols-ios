//
//  AudioEffects.swift
//  Player
//
//  Model for audio effects: speed and pitch.
//

import Foundation

/// Represents the current audio effect settings.
public struct AudioEffects: Equatable, Sendable {
    /// Playback speed multiplier (0.25x – 2.0x). Default is 1.0.
    public var speed: Float

    /// Pitch shift in cents (-1200 to +1200, i.e. ±1 octave). Default is 0.
    public var pitch: Float

    public static let `default` = AudioEffects(
        speed: 1.0,
        pitch: 0
    )
}
