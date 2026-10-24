//
//  PlayerDragState.swift
//  Volspire
//
//  The expanded player's per-frame gesture values. They live in an
//  observable object (not `@State` on the player) and are read only by the
//  small modifiers that apply them — so a dismiss / panel drag re-renders
//  those modifiers each frame instead of the whole player tree.
//

import DesignSystem
import SwiftUI

@Observable @MainActor
final class PlayerDragState {
    /// Dismiss drag: how far the card follows the finger down.
    var offsetY: CGFloat = 0
    /// Panel swipe: live horizontal offset of the artwork ⇄ comments pager.
    var pageDragX: CGFloat = 0
    /// 1 = fully expanded, animated toward 0 on collapse and following a
    /// dismiss drag — `ExpandProgressTracker` reports when it lands at 1.
    var expandTrack: CGFloat = 0

    /// Freezes the comments list while a dismiss drag is under way. Written
    /// only on change — observers re-render on every write.
    private(set) var commentsScrollLocked = false
    func setCommentsScrollLocked(_ locked: Bool) {
        if commentsScrollLocked != locked { commentsScrollLocked = locked }
    }

    // Per-gesture bookkeeping — read only by the gesture handlers.
    @ObservationIgnored var axis: Axis?
    /// Translation already accumulated when the axis locked, so the card
    /// follows the finger from 0 instead of jumping by the dead zone.
    @ObservationIgnored var baselineY: CGFloat = 0
    /// This vertical drag may dismiss (vs. scroll the comments list).
    @ObservationIgnored var dismissArmed = false
    /// Full-screen mode: this drag began at the top edge, so it dismisses
    /// instead of paging tracks.
    @ObservationIgnored var dismissFromTop = false

    func resetGesture() {
        axis = nil
        baselineY = 0
        dismissArmed = false
        dismissFromTop = false
    }
}

// MARK: - Effects

// The effects read the drag inside a View body (a modifier's
// `body(content:)` doesn't pick up observation reliably); the content passes
// through untouched, so only these small hosts re-render per frame.

/// The card's dismiss offset.
struct DismissDragEffect: ViewModifier {
    let drag: PlayerDragState
    func body(content: Content) -> some View {
        DismissDragHost(drag: drag, content: content)
    }
}

private struct DismissDragHost<Content: View>: View {
    let drag: PlayerDragState
    let content: Content
    var body: some View {
        content.offset(y: drag.offsetY)
    }
}

/// Slides the artwork ⇄ comments pager to `panel`, plus the live drag.
struct PagerOffsetEffect: ViewModifier {
    let drag: PlayerDragState
    let panel: Int
    let width: CGFloat
    func body(content: Content) -> some View {
        PagerOffsetHost(drag: drag, panel: panel, width: width, content: content)
    }
}

private struct PagerOffsetHost<Content: View>: View {
    let drag: PlayerDragState
    let panel: Int
    let width: CGFloat
    let content: Content
    var body: some View {
        content.offset(x: -CGFloat(panel) * width + drag.pageDragX)
    }
}

/// 0 on the artwork panel → 1 on the comments panel, tracking the live swipe.
@MainActor
func commentsProgress(panel: Int, drag: PlayerDragState) -> Double {
    let width = UIScreen.size.width
    guard width > 0 else { return Double(panel) }
    return Double(min(max(CGFloat(panel) - drag.pageDragX / width, 0), 1))
}

/// Blurs a full-bleed layer (video / visualizer) as the comments panel slides
/// over it, so the list reads. Its cost only applies while comments are open.
/// Stays mounted and fades via opacity — an unmounting material blinks out
/// instead of fading.
struct CommentsDimLayer: View {
    let drag: PlayerDragState
    let panel: Int
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(commentsProgress(panel: panel, drag: drag))
            .allowsHitTesting(false)
    }
}

/// Reports when `drag.expandTrack` has animated all the way to 1 — the
/// moment the card is fully expanded (square corners). Hosting it here keeps
/// the per-frame animation out of the player's body; the preference handler
/// only writes on a change.
struct ExpandProgressTracker: View {
    let drag: PlayerDragState
    var body: some View {
        ProgressTracker(progress: drag.expandTrack)
    }
}

private struct ProgressTracker: View, @preconcurrency Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .preference(key: NowPlayingExpandProgressPreferenceKey.self, value: progress)
    }
}

struct NowPlayingExpandProgressPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
