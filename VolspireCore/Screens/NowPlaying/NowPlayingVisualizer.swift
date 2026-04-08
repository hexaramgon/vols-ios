//
//  NowPlayingVisualizer.swift
//  Volspire
//
//  A real-time audio visualizer using AudioKit's GPU-accelerated Waveform view.
//  Displays a rolling waveform generated from live PCM audio data.
//

import SwiftUI
import Waveform

struct NowPlayingVisualizer: View {
    let spectrum: [Float]
    let albumArtwork: Image?
    let isPlaying: Bool
    var backgroundColor: Color = .black
    var rawSamples: [Float] = []

    /// Compute a high-contrast color against the background.
    private var waveformColor: Color {
        let uiColor = UIColor(backgroundColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let newHue = (h + 0.5).truncatingRemainder(dividingBy: 1.0)
        let newBrightness: CGFloat = b > 0.5 ? 0.15 : 1.0
        let newSaturation: CGFloat = max(s, 0.6)

        return Color(hue: Double(newHue), saturation: Double(newSaturation), brightness: Double(newBrightness))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dim album art as background
                if let albumArtwork {
                    albumArtwork
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 40)
                        .opacity(0.3)
                        .clipped()
                }

                // GPU-accelerated waveform
                Waveform(samples: SampleBuffer(samples: currentSamples))
                    .foregroundColor(waveformColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Provides samples for the waveform – uses the rolling buffer directly.
    private var currentSamples: [Float] {
        if !rawSamples.isEmpty {
            return rawSamples
        }
        // Fallback: synthesize from FFT spectrum when no raw samples available
        guard !spectrum.isEmpty else {
            return [Float](repeating: 0, count: 128)
        }
        let samplesPerBand = 32
        var result = [Float]()
        result.reserveCapacity(spectrum.count * samplesPerBand)
        for value in spectrum {
            let amplitude = (value * 2 - 1)
            for j in 0..<samplesPerBand {
                let phase = Float(j) / Float(samplesPerBand) * .pi * 4
                result.append(amplitude * sin(phase))
            }
        }
        return result
    }
}

#Preview {
    NowPlayingVisualizer(
        spectrum: (0 ..< 64).map { _ in Float.random(in: 0 ... 1) },
        albumArtwork: nil,
        isPlaying: true,
        rawSamples: (0..<8192).map { i in sin(Float(i) * 0.05) * Float.random(in: 0.3...1.0) }
    )
    .frame(width: 350, height: 350)
    .background(Color.black)
}
