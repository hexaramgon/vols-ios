//
//  EqualizerNode.swift
//  Player
//
//  Wraps one `AVAudioUnitEQ` as an AudioKit node so all the bands live in a
//  single audio unit. Always in the signal path: switching the unit's bypass
//  on/off mid-playback clicks (measured), and at flat every band is 0 dB so
//  it passes audio through unchanged. Band shapes must match
//  `AudioEqualizer.response`, which draws the curve.
//

import AudioKit
import AVFoundation

final class EqualizerNode: Node {
    private let input: Node
    private let unit = AVAudioUnitEQ(numberOfBands: AudioEqualizer.bands.count)

    var connections: [Node] { [input] }
    var avAudioNode: AVAudioNode { unit }

    init(_ input: Node) {
        self.input = input

        for (band, spec) in zip(unit.bands, AudioEqualizer.bands) {
            band.frequency = spec.defaultFrequency
            band.gain = 0
            band.bypass = false
            switch spec.shape {
            case .lowShelf:
                band.filterType = .lowShelf
            case .highShelf:
                band.filterType = .highShelf
            case .peak:
                band.filterType = .parametric
                band.bandwidth = AudioEqualizer.peakBandwidth
            }
        }
        unit.bypass = false
    }

    func apply(_ equalizer: AudioEqualizer) {
        for (band, (gain, frequency)) in zip(unit.bands, zip(equalizer.gains, equalizer.frequencies)) {
            band.frequency = frequency
            band.gain = gain
        }
        // Headroom: pull the level down by the largest boost so a loud master
        // doesn't get pushed into the limiter. Cuts need no compensation.
        unit.globalGain = -equalizer.maximumBoost
    }
}
