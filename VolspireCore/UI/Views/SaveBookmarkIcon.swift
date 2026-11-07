//
//  SaveBookmarkIcon.swift
//  Volspire
//
//  THE save bookmark glyph — every save toggle (listing cards + page, track
//  rows, Now Playing) draws it, so saving looks the same everywhere. Saving
//  plays a small beat: the glyph squashes, bounces a touch past full size
//  and settles while it fills `vSaved` (the primary blue) (no ripple — Hector kept it
//  simple). Unsaving just fades back to the outline. Reduce Motion: the
//  colour change only.
//

import DesignSystem
import SwiftUI

struct SaveBookmarkIcon: View {
    let saved: Bool
    var size: CGFloat = 22
    /// The outline's colour while unsaved.
    var idleColor: Color = .inkText(0.78)
    /// The fill while saved (the player overrides it — white there for now).
    var savedColor: Color = .vSaved

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped on every save → plays the pop once.
    @State private var saveBeat = 0
    /// When this glyph appeared — a flip to saved right after it (the page's
    /// saved state loading in) isn't a save, so it doesn't pop.
    @State private var appearedAt = Date.distantFuture

    var body: some View {
        LucideIcon(saved ? .bookmarkFill : .bookmark, size: size)
            .foregroundStyle(saved ? savedColor : idleColor)
            // The state loading in just shows; only a real toggle fades.
            .animation(Date.now.timeIntervalSince(appearedAt) > 1 ? .easeOut(duration: 0.18) : nil, value: saved)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: saveBeat) { glyph, scale in
                glyph.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.78, duration: 0.08)
                    SpringKeyframe(1.22, duration: 0.16, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.22, spring: .bouncy)
                }
            }
            .onAppear { appearedAt = .now }
            .onChange(of: saved) { was, now in
                // Only a real save pops: not reduce-motion, and not the
                // state arriving as the screen loads (within ~1s of showing).
                guard now, !was, !reduceMotion,
                      Date.now.timeIntervalSince(appearedAt) > 1 else { return }
                saveBeat += 1
            }
    }

}
