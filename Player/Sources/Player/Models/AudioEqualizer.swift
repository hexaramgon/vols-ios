//
//  AudioEqualizer.swift
//  Player
//
//  Model for the five-band playback EQ: each band has a gain and a frequency
//  the user can move within that band's range. Separate from `AudioEffects`
//  because it's a listening preference: speed resets per track, EQ stays on
//  (and is saved between sessions by the app).
//
//  `response(atFrequency:)` is the curve the EQ screen draws. It uses the
//  standard RBJ biquad formulas with the same shapes as `EqualizerNode`, so
//  the picture matches what you hear.
//

import Foundation

public struct AudioEqualizer: Equatable, Sendable, Codable {
    public struct Band: Identifiable, Sendable {
        public enum Shape: Sendable {
            case lowShelf, peak, highShelf
        }

        public let label: String
        public let shape: Shape
        public let defaultFrequency: Float
        /// Where the band's point can be dragged. Neighbouring ranges barely
        /// overlap, so points keep their left-to-right order.
        public let frequencyRange: ClosedRange<Float>

        public var id: String { label }
    }

    public static let bands: [Band] = [
        Band(label: "Low", shape: .lowShelf, defaultFrequency: 60, frequencyRange: 30 ... 200),
        Band(label: "Low mid", shape: .peak, defaultFrequency: 250, frequencyRange: 120 ... 700),
        Band(label: "Mid", shape: .peak, defaultFrequency: 1000, frequencyRange: 500 ... 2500),
        Band(label: "High mid", shape: .peak, defaultFrequency: 4000, frequencyRange: 2000 ... 8000),
        Band(label: "High", shape: .highShelf, defaultFrequency: 12000, frequencyRange: 6000 ... 16000)
    ]

    /// Per-band limit in dB.
    public static let gainRange: ClosedRange<Float> = -12 ... 12
    /// Width of the peak bands, in octaves.
    public static let peakBandwidth: Float = 1.5

    public static let flat = AudioEqualizer(gains: [])

    /// Gain in dB for each of `bands`, in the same order.
    public private(set) var gains: [Float]
    /// Centre / corner frequency in Hz for each of `bands`.
    public private(set) var frequencies: [Float]

    /// Clamps everything to the band ranges. Lists that don't match the band
    /// count (a value saved under a different layout) fall back to defaults.
    public init(gains: [Float], frequencies: [Float]? = nil) {
        let bands = Self.bands
        self.gains = gains.count == bands.count
            ? gains.map { min(max($0, Self.gainRange.lowerBound), Self.gainRange.upperBound) }
            : bands.map { _ in 0 }
        let freqs = frequencies ?? []
        self.frequencies = zip(bands.indices, bands).map { index, band in
            guard freqs.count == bands.count else { return band.defaultFrequency }
            return min(max(freqs[index], band.frequencyRange.lowerBound), band.frequencyRange.upperBound)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            gains: (try? container.decode([Float].self, forKey: .gains)) ?? [],
            frequencies: try? container.decode([Float].self, forKey: .frequencies)
        )
    }

    /// A copy with one band's gain changed.
    public func settingGain(_ gain: Float, forBand index: Int) -> AudioEqualizer {
        var next = gains
        next[index] = gain
        return AudioEqualizer(gains: next, frequencies: frequencies)
    }

    /// A copy with one band moved.
    public func settingFrequency(_ frequency: Float, forBand index: Int) -> AudioEqualizer {
        var next = frequencies
        next[index] = frequency
        return AudioEqualizer(gains: gains, frequencies: next)
    }

    public var isFlat: Bool {
        gains.allSatisfy { $0 == 0 }
    }

    /// The largest boost across all bands, in dB (0 when nothing is boosted).
    public var maximumBoost: Float {
        gains.max().map { max($0, 0) } ?? 0
    }

    // MARK: - Response curve

    /// Combined EQ gain in dB at `frequency` (all bands, before the headroom
    /// trim the player applies).
    public func response(atFrequency frequency: Double, sampleRate: Double = 48000) -> Double {
        zip(Self.bands.indices, Self.bands).reduce(0) { total, item in
            let (index, band) = item
            return total + Self.bandResponse(
                shape: band.shape,
                gain: Double(gains[index]),
                center: Double(frequencies[index]),
                at: frequency,
                sampleRate: sampleRate
            )
        }
    }

    private static func bandResponse(
        shape: Band.Shape, gain: Double, center: Double, at frequency: Double, sampleRate: Double
    ) -> Double {
        guard gain != 0 else { return 0 }
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * center / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let b0, b1, b2, a0, a1, a2: Double

        switch shape {
        case .peak:
            let bandwidth = Double(peakBandwidth)
            let alpha = sinW0 * sinh(log(2) / 2 * bandwidth * w0 / sinW0)
            b0 = 1 + alpha * a
            b1 = -2 * cosW0
            b2 = 1 - alpha * a
            a0 = 1 + alpha / a
            a1 = -2 * cosW0
            a2 = 1 - alpha / a
        case .lowShelf, .highShelf:
            // Shelf slope S = 1.
            let alpha = sinW0 / 2 * sqrt(2)
            let twoRootAAlpha = 2 * sqrt(a) * alpha
            if shape == .lowShelf {
                b0 = a * ((a + 1) - (a - 1) * cosW0 + twoRootAAlpha)
                b1 = 2 * a * ((a - 1) - (a + 1) * cosW0)
                b2 = a * ((a + 1) - (a - 1) * cosW0 - twoRootAAlpha)
                a0 = (a + 1) + (a - 1) * cosW0 + twoRootAAlpha
                a1 = -2 * ((a - 1) + (a + 1) * cosW0)
                a2 = (a + 1) + (a - 1) * cosW0 - twoRootAAlpha
            } else {
                b0 = a * ((a + 1) + (a - 1) * cosW0 + twoRootAAlpha)
                b1 = -2 * a * ((a - 1) + (a + 1) * cosW0)
                b2 = a * ((a + 1) + (a - 1) * cosW0 - twoRootAAlpha)
                a0 = (a + 1) - (a - 1) * cosW0 + twoRootAAlpha
                a1 = 2 * ((a - 1) - (a + 1) * cosW0)
                a2 = (a + 1) - (a - 1) * cosW0 - twoRootAAlpha
            }
        }

        // |H(e^jw)| for the biquad, in dB.
        let w = 2 * Double.pi * frequency / sampleRate
        let (c1, s1, c2, s2) = (cos(w), sin(w), cos(2 * w), sin(2 * w))
        let numRe = b0 + b1 * c1 + b2 * c2
        let numIm = -(b1 * s1 + b2 * s2)
        let denRe = a0 + a1 * c1 + a2 * c2
        let denIm = -(a1 * s1 + a2 * s2)
        let magnitude = sqrt(numRe * numRe + numIm * numIm) / sqrt(denRe * denRe + denIm * denIm)
        return 20 * log10(magnitude)
    }
}

public enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case flat, bass, vocal, bright, warm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flat: "Flat"
        case .bass: "Bass"
        case .vocal: "Vocal"
        case .bright: "Bright"
        case .warm: "Warm"
        }
    }

    /// Presets use each band's default frequency.
    public var equalizer: AudioEqualizer {
        switch self {
        case .flat: .flat
        case .bass: AudioEqualizer(gains: [6, 2, 0, 0, 0])
        case .vocal: AudioEqualizer(gains: [-2, -1, 3, 2, 0])
        case .bright: AudioEqualizer(gains: [0, 0, 0, 2, 5])
        case .warm: AudioEqualizer(gains: [3, 2, 0, -2, -3])
        }
    }

    /// The preset these exact settings match, if any.
    public init?(matching equalizer: AudioEqualizer) {
        guard let match = Self.allCases.first(where: { $0.equalizer == equalizer }) else { return nil }
        self = match
    }
}
