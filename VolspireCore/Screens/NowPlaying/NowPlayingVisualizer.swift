//
//  NowPlayingVisualizer.swift
//  Volspire
//
//  A real-time audio visualizer displayed in place of album artwork
//  when there is no video. Uses FFT spectrum data from the audio tap.
//

import SwiftUI

struct NowPlayingVisualizer: View {
    let spectrum: [Float]
    let albumArtwork: Image?
    let isPlaying: Bool

    private let barCount = 48
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let bands = resample(spectrum, to: barCount)
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

                // Spectrum bars
                HStack(alignment: .center, spacing: barSpacing) {
                    ForEach(0 ..< barCount, id: \.self) { index in
                        VisualizerBar(
                            value: CGFloat(bands[index]),
                            maxHeight: geo.size.height * 0.85,
                            index: index,
                            total: barCount
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Resample spectrum to desired bar count.
    private func resample(_ spectrum: [Float], to count: Int) -> [Float] {
        guard !spectrum.isEmpty, count > 0 else {
            return [Float](repeating: 0, count: count)
        }
        if spectrum.count == count { return spectrum }

        var result = [Float](repeating: 0, count: count)
        let ratio = Float(spectrum.count) / Float(count)
        for i in 0 ..< count {
            let start = Int(Float(i) * ratio)
            let end = min(Int(Float(i + 1) * ratio), spectrum.count)
            let slice = spectrum[start ..< max(start + 1, end)]
            result[i] = slice.max() ?? 0
        }
        return result
    }
}

private struct VisualizerBar: View {
    let value: CGFloat
    let maxHeight: CGFloat
    let index: Int
    let total: Int

    var body: some View {
        let minHeight: CGFloat = 3
        let height = max(minHeight, value * maxHeight)

        // Color gradient from center outward
        let center = CGFloat(total) / 2
        let distance = abs(CGFloat(index) - center) / center
        let hue = 0.55 - Double(distance) * 0.15 // Blue-ish to teal-ish

        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.7, brightness: 0.95),
                        Color(hue: hue + 0.08, saturation: 0.5, brightness: 0.75),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: height)
            .animation(.easeOut(duration: 0.08), value: value)
    }
}

#Preview {
    NowPlayingVisualizer(
        spectrum: (0 ..< 64).map { _ in Float.random(in: 0 ... 1) },
        albumArtwork: nil,
        isPlaying: true
    )
    .frame(width: 350, height: 350)
    .background(Color.black)
}
