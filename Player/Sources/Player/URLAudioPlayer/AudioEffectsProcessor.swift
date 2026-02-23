//
//  AudioEffectsProcessor.swift
//  Player
//
//  Manages audio effects via AudioKit's TimePitch node.
//  Speed and pitch are controlled independently (unlike AVPlayer's varispeed).
//

import AudioKit
import AVFoundation

@MainActor
public final class AudioEffectsProcessor {
    public private(set) var currentEffects: AudioEffects = .default

    public init() {}

    /// Apply effects to the AudioKit TimePitch node.
    public func apply(_ effects: AudioEffects, to timePitch: TimePitch) {
        currentEffects = effects
        timePitch.rate = AUValue(effects.speed)
        timePitch.pitch = AUValue(effects.pitch)
    }

    /// Re-apply the current effects (e.g. after resuming).
    public func reapply(to timePitch: TimePitch) {
        apply(currentEffects, to: timePitch)
    }

    /// Get the effective playback rate combining speed and pitch.
    public var playbackRate: Float {
        currentEffects.speed
    }
}
