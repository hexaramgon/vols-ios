//
//  AudioSpectrumAnalyzer.swift
//  Player
//
//  Real-time FFT spectrum analysis using Accelerate/vDSP.
//  Receives PCM audio data and produces frequency band magnitudes.
//

import Accelerate
import AVFoundation

@MainActor
public final class AudioSpectrumAnalyzer {
    public static let defaultBandCount = 64

    private let fftSetup: vDSP.FFT<DSPSplitComplex>
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let bandCount: Int
    private var magnitudes: [Float]

    /// Smoothing factor: 0 = no smoothing, 1 = frozen.
    private let smoothing: Float = 0.7

    public init(bandCount: Int = AudioSpectrumAnalyzer.defaultBandCount) {
        self.bandCount = bandCount
        // Use 2048-point FFT — good balance of frequency resolution vs latency
        self.fftSize = 2048
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
        self.magnitudes = [Float](repeating: 0, count: bandCount)
    }

    /// Process raw float samples (non-interleaved per-channel or mono) and return band magnitudes in [0...1].
    public func analyzeRaw(samples: [Float], channelCount: Int) -> [Float] {
        guard !samples.isEmpty else { return magnitudes }

        var monoSamples = [Float](repeating: 0, count: fftSize)
        let frameCount = samples.count / max(channelCount, 1)
        let samplesToProcess = min(frameCount, fftSize)

        if channelCount >= 2 {
            // Non-interleaved: first half is left channel, second half is right
            // But from our tap it's actually separate buffers copied sequentially
            // so just use the first channel's worth of data
            for i in 0 ..< samplesToProcess {
                monoSamples[i] = samples[i]
            }
        } else {
            for i in 0 ..< samplesToProcess {
                monoSamples[i] = samples[i]
            }
        }

        return performFFT(on: &monoSamples)
    }

    /// Reset all magnitudes to zero.
    public func reset() {
        magnitudes = [Float](repeating: 0, count: bandCount)
    }
}

// MARK: - FFT Core

private extension AudioSpectrumAnalyzer {
    func performFFT(on monoSamples: inout [Float]) -> [Float] {
        // Apply Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(monoSamples, 1, window, 1, &monoSamples, 1, vDSP_Length(fftSize))

        // Prepare split complex buffers for FFT
        let halfN = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                // Pack interleaved real data into split complex form
                monoSamples.withUnsafeBufferPointer { sampleBuf in
                    sampleBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }

                // Perform forward FFT
                fftSetup.forward(input: splitComplex, output: &splitComplex)

                // Compute magnitudes
                var fftMagnitudes = [Float](repeating: 0, count: halfN)
                vDSP_zvmags(&splitComplex, 1, &fftMagnitudes, 1, vDSP_Length(halfN))

                // Convert to dB scale
                var one: Float = 1.0
                vDSP_vdbcon(fftMagnitudes, 1, &one, &fftMagnitudes, 1, vDSP_Length(halfN), 1)

                // Map FFT bins to our desired band count (logarithmic distribution)
                let bands = mapToBands(fftMagnitudes, bandCount: bandCount)

                // Smooth with previous values
                for i in 0 ..< bandCount {
                    magnitudes[i] = smoothing * magnitudes[i] + (1 - smoothing) * bands[i]
                }
            }
        }

        return magnitudes
    }

    /// Map linear FFT bins to logarithmically-spaced frequency bands, normalized to [0...1].
    func mapToBands(_ fftMagnitudes: [Float], bandCount: Int) -> [Float] {
        let binCount = fftMagnitudes.count
        var bands = [Float](repeating: 0, count: bandCount)

        // dB range: -80 dB (silence) to 0 dB (max)
        let minDB: Float = -80
        let maxDB: Float = 0

        for i in 0 ..< bandCount {
            // Logarithmic bin range for this band
            let lowFraction = pow(Float(i) / Float(bandCount), 2.0)
            let highFraction = pow(Float(i + 1) / Float(bandCount), 2.0)
            let lowBin = Int(lowFraction * Float(binCount))
            let highBin = max(Int(highFraction * Float(binCount)), lowBin + 1)
            let clampedHigh = min(highBin, binCount)

            // Average the bins in this range
            var sum: Float = 0
            var count: Float = 0
            for bin in lowBin ..< clampedHigh {
                sum += fftMagnitudes[bin]
                count += 1
            }
            let avgDB = count > 0 ? sum / count : minDB

            // Normalize dB to [0...1]
            let normalized = (avgDB - minDB) / (maxDB - minDB)
            bands[i] = max(0, min(1, normalized))
        }

        return bands
    }
}
