import Accelerate
import Foundation

/// Turns raw samples into MilkDrop-style band levels. The FFT runs on
/// Accelerate/vDSP; the equalize curve and the bass/mid/treb attenuation
/// dynamics are ported from butterchurn (fft.js / audioLevels.js) so presets
/// written against MilkDrop semantics behave identically: band values are
/// ratios against a slow-moving average, ≈1 at steady state.
final class AudioAnalyzer {
    private let fftSize = 1024
    private let binCount = 512

    private let fftSetup: FFTSetup
    private var windowReal: [Float]
    private var windowImag: [Float]
    private var magnitudes: [Float]
    private let equalize: [Float]

    // Band boundaries in FFT bins, set from the tap's sample rate.
    private var starts = [0, 0, 0]
    private var stops = [0, 0, 0]
    private var configuredSampleRate: Float = 0

    // Smoothing state (butterchurn audioLevels)
    private var imm = [Float](repeating: 0, count: 3)
    private var avg = [Float](repeating: 1, count: 3)
    private var longAvg = [Float](repeating: 1, count: 3)

    init() {
        guard let setup = vDSP_create_fftsetup(vDSP_Length(10), FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP FFT setup failed")
        }
        fftSetup = setup
        windowReal = [Float](repeating: 0, count: binCount)
        windowImag = [Float](repeating: 0, count: binCount)
        magnitudes = [Float](repeating: 0, count: binCount)

        // butterchurn's equalize curve: emphasizes highs, zeroes the DC bin.
        var eq = [Float](repeating: 0, count: binCount)
        let inv = 1.0 / Float(binCount)
        for i in 0..<binCount {
            eq[i] = -0.02 * log(Float(binCount - i) * inv)
        }
        equalize = eq
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    private func configureBands(sampleRate: Float) {
        configuredSampleRate = sampleRate
        let bucketHz = sampleRate / Float(fftSize)
        func bin(_ hz: Float) -> Int {
            min(max(Int((hz / bucketHz).rounded()) - 1, 0), binCount - 1)
        }
        let bassLow = bin(20), bassHigh = bin(320), midHigh = bin(2800), trebHigh = bin(11025)
        starts = [bassLow, bassHigh, midHigh]
        stops = [bassHigh, midHigh, trebHigh]
    }

    /// - Parameters:
    ///   - samples: 1024 mono samples in [-1, 1]
    ///   - rightSamples: 1024 right-channel samples (equals mono if mono source)
    ///   - fps: current measured frame rate (smoothing is FPS-compensated)
    ///   - frame: frame counter (early frames converge faster)
    /// Updates `audio`'s six band fields in place.
    func update(_ audio: inout AudioFrame, samples: [Float], rightSamples: [Float],
                sampleRate: Float, fps: Float, frame: Int) {
        if sampleRate != configuredSampleRate {
            configureBands(sampleRate: sampleRate)
        }

        // Real FFT (zrip packs even/odd; magnitudes are what MilkDrop wants —
        // absolute scale cancels out of the ratios below).
        samples.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { complexPtr in
                windowReal.withUnsafeMutableBufferPointer { re in
                    windowImag.withUnsafeMutableBufferPointer { im in
                        var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(binCount))
                        vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(10), FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(binCount))
                    }
                }
            }
        }
        vDSP_vmul(magnitudes, 1, equalize, 1, &magnitudes, 1, vDSP_Length(binCount))

        let effectiveFPS = min(max(fps.isFinite ? fps : 30, 15), 144)

        for band in 0..<3 {
            var sum: Float = 0
            for i in starts[band]..<stops[band] { sum += magnitudes[i] }
            imm[band] = sum

            // Fast average: attack 0.2, release 0.5 (at 30fps reference)
            var rate: Float = imm[band] > avg[band] ? 0.2 : 0.5
            rate = pow(rate, 30.0 / effectiveFPS)
            avg[band] = avg[band] * rate + imm[band] * (1 - rate)

            // Long average: the "what's normal" baseline
            rate = frame < 50 ? 0.9 : 0.992
            rate = pow(rate, 30.0 / effectiveFPS)
            longAvg[band] = longAvg[band] * rate + imm[band] * (1 - rate)

            let val: Float
            let att: Float
            if longAvg[band] < 0.001 {
                val = 1; att = 1
            } else {
                val = imm[band] / longAvg[band]
                att = avg[band] / longAvg[band]
            }
            switch band {
            case 0: audio.bass = val; audio.bassAtt = att
            case 1: audio.mid = val; audio.midAtt = att
            default: audio.treb = val; audio.trebAtt = att
            }
        }

        // Waveform for drawing: 2:1 downsample with the same neighbor
        // smoothing butterchurn applies in processAudio.
        var prev: Float = samples[0]
        var prevR: Float = rightSamples[0]
        for i in 0..<512 {
            let s = samples[i * 2]
            audio.waveform[i] = 0.5 * (s + prev)
            prev = samples[min(i * 2 + 1, 1023)]
            let r = rightSamples[i * 2]
            audio.waveformR[i] = 0.5 * (r + prevR)
            prevR = rightSamples[min(i * 2 + 1, 1023)]
        }
    }
}
