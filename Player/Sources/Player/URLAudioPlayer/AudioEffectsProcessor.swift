//
//  AudioEffectsProcessor.swift
//  Player
//
//  Reproduces the web app's `playbackRate` + `preservesPitch` behavior using
//  two nodes so each mode uses the right algorithm:
//   • preserve pitch ON  → TimePitch (phase-vocoder time-stretch, pitch held)
//   • preserve pitch OFF → VariSpeed (resampling, pitch follows speed)
//  Routing the varispeed case through resampling — instead of a simultaneous
//  time-stretch + pitch-shift on TimePitch — avoids the phasey/"echoey"
//  artifacts that stacking both phase-vocoder operations produces.
//

import AudioKit
import AVFoundation
import Foundation

@MainActor
final class AudioEffectsProcessor {
    private(set) var currentEffects: AudioEffects = .default

    init() {}

    /// Apply effects across the VariSpeed + TimePitch pair. Only one node is
    /// ever non-neutral; the unused node is reset to 1.0 first so speed is never
    /// momentarily applied twice while switching modes.
    func apply(_ effects: AudioEffects, variSpeed: VariSpeed, timePitch: TimePitch) {
        currentEffects = effects
        let rate = AUValue(effects.speed)

        if effects.preservePitch {
            // Tempo only — bypass resampling, stretch with the phase vocoder.
            variSpeed.rate = 1
            timePitch.pitch = 0
            timePitch.rate = rate
        } else {
            // Varispeed — bypass the phase vocoder, resample cleanly.
            timePitch.rate = 1
            timePitch.pitch = 0
            variSpeed.rate = rate
        }
    }

    /// Re-apply the current effects (e.g. after resuming or seeking).
    func reapply(variSpeed: VariSpeed, timePitch: TimePitch) {
        apply(currentEffects, variSpeed: variSpeed, timePitch: timePitch)
    }

    /// Effective playback rate (speed), used to keep the muted video layer in sync.
    var playbackRate: Float {
        currentEffects.speed
    }
}
