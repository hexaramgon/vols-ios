//
//  MediaActivityIndicator.swift
//  Volspire
//
//

import SwiftUI

enum MediaActivity {
    case paused
    case buffering
    case playing
}

/// Small static "now playing" marker shown over the active track's artwork in
/// lists. Replaces the old FFT-driven equalizer — fixed bars, no spectrum and no
/// per-frame work.
struct MediaActivityIndicator: View {
    let state: MediaActivity

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .frame(width: 2.5, height: 22 * height)
            }
        }
        .frame(width: 16, height: 22)
    }

    private var barHeights: [CGFloat] {
        switch state {
        case .playing: [0.45, 0.9, 0.6, 0.8]
        case .paused, .buffering: [0.3, 0.3, 0.3, 0.3]
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VStack {
        MediaActivityIndicator(state: .paused)
        MediaActivityIndicator(state: .buffering)
        MediaActivityIndicator(state: .playing)
    }
    .foregroundStyle(.white)
    .padding(10)
    .background(Color.gray)
}
