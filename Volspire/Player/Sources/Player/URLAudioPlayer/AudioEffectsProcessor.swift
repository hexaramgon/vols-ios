//
//  AudioEffectsProcessor.swift
//  Player
//
//  Manages audio effects applied to AVPlayer playback.
//  Speed + Pitch: AVPlayer.rate with .varispeed time pitch algorithm
//  (rate changes shift pitch naturally, like vinyl/tape speed control)
//

import AVFoundation

@MainActor
public final class AudioEffectsProcessor {
    private(set) var currentEffects: AudioEffects = .default

    public init() {}

    /// Apply effects to the given AVPlayer.
    public func apply(_ effects: AudioEffects, to player: AVPlayer?) {
        currentEffects = effects

        guard let player else { return }

        // Use varispeed: rate changes also shift pitch (vinyl / tape style)
        player.currentItem?.audioTimePitchAlgorithm = .varispeed

        // Compute effective rate: speed × pitch adjustment
        // Pitch in cents → rate multiplier: rate = 2^(cents/1200)
        let pitchRate = pow(2.0, effects.pitch / 1200.0)
        let effectiveRate = effects.speed * pitchRate

        // Only change rate if player is currently playing
        if player.rate != 0 {
            player.rate = effectiveRate
        }
    }

    /// Get the effective playback rate combining speed and pitch.
    public var playbackRate: Float {
        let pitchRate = pow(2.0, currentEffects.pitch / 1200.0)
        return currentEffects.speed * pitchRate
    }
}
