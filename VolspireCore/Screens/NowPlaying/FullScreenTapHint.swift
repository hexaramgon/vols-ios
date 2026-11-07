//
//  FullScreenTapHint.swift
//  Volspire
//
//  One-time coach mark for the expanded player's full-screen mode (a tap on
//  empty space tucks the controls away). It shows once, the first time the
//  player is open on its main panel with a track playing: a dimmed stage, a
//  pointer tapping with a ripple, and a caption.
//  Any tap dismisses it for good — and that tap enters full-screen mode, so
//  the hint demonstrates itself. Step two then follows once, in full-screen
//  mode: a hand swiping up — "Swipe up for the next track" (the feed swipe).
//  And once, the first time the open player moves to another track (any way
//  — a swipe, next, autoplay): a hand sweeping left — "Swipe left for
//  comments" (`CommentsSwipeHintHost`).
//  The swipe hints only go away with the swipe they teach: the drag is
//  handed to the player underneath (the next track / the comments ride the
//  finger as the hint fades), and letting go past the threshold does the
//  real thing. Taps and other directions are ignored.
//

import DesignSystem
import SwiftUI

enum FullScreenTapHint {
    private static let seenKey = "volspire:hint:fullscreen-tap-seen"

    /// Not seen on this device yet. (Showing also needs a track playing in
    /// the expanded player — ExpandableNowPlaying's `tapHintWindow`.)
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: seenKey) }

    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }
}

struct FullScreenTapHintOverlay: View {
    let onTap: () -> Void

    @State private var pressed = false
    @State private var ripple = false

    var body: some View {
        ZStack {
            // Dark enough that the player behind never fights the caption.
            DimBackdrop()

            VStack(spacing: 22) {
                ZStack {
                    // The tap's ripple, from the fingertip.
                    Circle()
                        .stroke(Color.white.opacity(ripple ? 0 : 0.55), lineWidth: 2)
                        .frame(width: 34, height: 34)
                        .scaleEffect(ripple ? 2.6 : 0.6)
                        .offset(x: -9, y: -22)
                    LucideIcon(.pointer, size: 64)
                        .foregroundStyle(.white)
                        .scaleEffect(pressed ? 0.86 : 1)
                        .offset(y: pressed ? 4 : 0)
                }
                .frame(width: 120, height: 120)

                VStack(spacing: 6) {
                    Text("Tap anywhere to go full screen")
                        .font(.appTitle3)
                        .foregroundStyle(.white)
                    Text("Tap again to bring the controls back.")
                        .font(.appBody)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .task { await loop() }
    }

    /// Press → release with a ripple, every ~1.4s, until dismissed.
    private func loop() async {
        while !Task.isCancelled {
            withAnimation(.easeIn(duration: 0.18)) { pressed = true }
            try? await Task.sleep(for: .milliseconds(180))
            ripple = false
            withAnimation(.easeOut(duration: 0.22)) { pressed = false }
            withAnimation(.easeOut(duration: 0.7)) { ripple = true }
            try? await Task.sleep(for: .milliseconds(1250))
        }
    }
}

/// Step two, in full-screen mode: an open hand sweeping up under a pair of
/// chevrons — "Swipe up for the next track". Only a swipe up gets past it (no
/// flag of its own: it only ever follows the one-time tap hint).
struct FullScreenSwipeHintOverlay: View {
    /// Live upward travel (≤ 0), for the feed to follow.
    let onDrag: (CGFloat) -> Void
    /// Let go, with the projected upward travel (≤ 0).
    let onRelease: (CGFloat) -> Void

    @State private var lifted = false
    @State private var visible = true
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            DimBackdrop()

            VStack(spacing: 22) {
                VStack(spacing: 4) {
                    // Direction cue, brightening as the hand sweeps toward it.
                    LucideIcon(.chevronsUp, size: 36)
                        .foregroundStyle(.white.opacity(lifted ? 0.9 : 0.3))
                    LucideIcon(.hand, size: 64)
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(lifted ? -8 : 0))
                        .offset(y: lifted ? -26 : 26)
                }
                .opacity(visible ? 1 : 0)
                .frame(width: 120, height: 150)

                VStack(spacing: 6) {
                    Text("Swipe up for the next track")
                        .font(.appTitle3)
                        .foregroundStyle(.white)
                    Text("Swipe down to go back.")
                        .font(.appBody)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
        // Fades as the next track comes up under it.
        .opacity(1 - progress * 0.9)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dy = min(value.translation.height, 0)
                    progress = min(-dy / 220, 1)
                    onDrag(dy)
                }
                .onEnded { value in
                    let projected = min(value.translation.height + value.velocity.height / 5, 0)
                    withAnimation(.smooth(duration: 0.25)) { progress = 0 }
                    onRelease(projected)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Next track") { onRelease(-.infinity) }
        .task { await loop() }
    }

    /// Slide up and fade, reset below, repeat every ~1.5s.
    private func loop() async {
        while !Task.isCancelled {
            lifted = false
            withAnimation(.easeOut(duration: 0.2)) { visible = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.6)) { lifted = true }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeIn(duration: 0.2)) { visible = false }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}

// MARK: - Step three: comments

enum CommentsSwipeHint {
    private static let seenKey = "volspire:hint:comments-swipe-seen"
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: seenKey) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }
}

/// Step three: an open hand sweeping left under a pair of chevrons — "Swipe
/// left for comments". Only a swipe left gets past it, sliding the comments
/// in under the finger.
struct CommentsSwipeHintOverlay: View {
    /// Live leftward travel (≤ 0), for the panels to follow.
    let onDrag: (CGFloat) -> Void
    /// Let go, with the projected leftward travel (≤ 0).
    let onRelease: (CGFloat) -> Void

    @State private var swept = false
    @State private var visible = true
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            DimBackdrop()

            VStack(spacing: 22) {
                HStack(spacing: 4) {
                    LucideIcon(.chevronsLeft, size: 36)
                        .foregroundStyle(.white.opacity(swept ? 0.9 : 0.3))
                    LucideIcon(.hand, size: 64)
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(swept ? -10 : 0))
                        .offset(x: swept ? -26 : 26)
                }
                .opacity(visible ? 1 : 0)
                .frame(width: 170, height: 120)

                VStack(spacing: 6) {
                    Text("Swipe left for comments")
                        .font(.appTitle3)
                        .foregroundStyle(.white)
                    Text("Swipe right to go back.")
                        .font(.appBody)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
        // Fades as the comments slide in under it.
        .opacity(1 - progress * 0.9)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dx = min(value.translation.width, 0)
                    progress = min(-dx / 180, 1)
                    onDrag(dx)
                }
                .onEnded { value in
                    let projected = min(value.translation.width + value.velocity.width / 6, 0)
                    withAnimation(.smooth(duration: 0.25)) { progress = 0 }
                    onRelease(projected)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open comments") { onRelease(-.infinity) }
        .task { await loop() }
    }

    /// Sweep left and fade, reset on the right, repeat every ~1.5s.
    private func loop() async {
        while !Task.isCancelled {
            swept = false
            withAnimation(.easeOut(duration: 0.2)) { visible = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.6)) { swept = true }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeIn(duration: 0.2)) { visible = false }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}

/// Hosts the comments hint on the player: the first time the track changes
/// while the player is open on its artwork panel, after a beat, once ever.
struct CommentsSwipeHintHost: ViewModifier {
    /// The playing track (its change = moving to another track).
    let trackId: String?
    /// Player open on the artwork, comments available (not a workspace file).
    let eligible: Bool
    /// Another coach mark is up — wait for the next track instead.
    let blocked: Bool
    /// The hint's leftward drag, for the panels to follow.
    let dragPanels: (CGFloat) -> Void
    /// Let go: open the comments (true) or spring back.
    let settlePanels: (_ open: Bool) -> Void

    @State private var show = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if show {
                    CommentsSwipeHintOverlay(onDrag: dragPanels) { projected in
                        // Same threshold as the player's own panel swipe.
                        let open = projected < -UIScreen.size.width * 0.2
                        settlePanels(open)
                        guard open else { return }
                        CommentsSwipeHint.markSeen()
                        withAnimation(.easeOut(duration: 0.2)) { show = false }
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: trackId) { old, new in
                guard old != nil, new != nil, eligible, CommentsSwipeHint.shouldShow else { return }
                Task {
                    // Let the new track settle in first.
                    try? await Task.sleep(for: .seconds(0.9))
                    guard eligible, !blocked, CommentsSwipeHint.shouldShow, !show else { return }
                    withAnimation(.easeOut(duration: 0.25)) { show = true }
                }
            }
            // Leaving full-screen / the player takes it with it.
            .onChange(of: eligible) { _, on in
                if !on, show { withAnimation(.easeOut(duration: 0.2)) { show = false } }
            }
    }
}
