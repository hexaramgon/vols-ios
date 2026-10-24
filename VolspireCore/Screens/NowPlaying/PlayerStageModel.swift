//
//  PlayerStageModel.swift
//  Volspire
//
//  Full-screen mode and the feed swipe, as one state machine. The stage is
//  the cover / video; full-screen mode tucks the controls away (tap to
//  toggle) and turns vertical drags into Reels-style track paging.
//
//  Per-frame values (`feedDragY`) are only read by `FeedStageEffect`, so a
//  drag re-renders that modifier, not the player.
//

import DesignSystem
import MediaLibrary
import SwiftUI

@Observable @MainActor
final class PlayerStageModel {
    // MARK: Full-screen mode

    /// Controls tucked away (title + scrubber only).
    private(set) var controlsMinimized = false
    /// Comments were opened from full-screen mode: the stage keeps its
    /// full-screen layout behind the panel, and closing it returns there.
    private(set) var restoreAfterComments = false

    /// Full-screen layout for the stage — also while comments opened from
    /// full-screen mode are up, so the stage never re-lays out under the panel.
    var stageFullScreen: Bool { controlsMinimized || restoreAfterComments }

    /// How far the title glides down when the controls tuck away (reported by
    /// `PlayerControls`). The cover + info strip drop by the same amount, so
    /// the strip keeps its exact gap above the title in full-screen mode.
    var fullScreenTitleDrop: CGFloat = 0

    func toggleFullScreen() {
        withAnimation(.easeInOut(duration: 0.3)) { controlsMinimized.toggle() }
    }

    /// The player is expanding: start with the controls showing. Reset here,
    /// not on collapse — un-minimizing mid-dismiss moved the stage while the
    /// card slid away.
    func playerWillExpand() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            controlsMinimized = false
            restoreAfterComments = false
        }
    }

    /// The comments panel opened (from either mode).
    func commentsDidOpen() {
        restoreAfterComments = controlsMinimized
        controlsMinimized = false
    }

    /// Back on the main panel: return to full-screen mode if that's where the
    /// viewer was. Minimize FIRST, in one transaction, so `stageFullScreen`
    /// never reads false between the writes (that frame snapped the cover).
    func commentsDidClose() {
        guard restoreAfterComments else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            controlsMinimized = true
            restoreAfterComments = false
        }
    }

    // MARK: Feed swipe

    // A vertical pager, TikTok-style (`FeedCoverPager`): every cover is a view
    // keyed by its TRACK, laid out one page apart around the centre track and
    // shifted by the drag. A swipe slides the next track's view into the
    // centre; landing re-centres on that same view (same id, same spot), so
    // nothing is swapped, rebuilt or reloaded — there's nothing to flash.

    /// Live vertical drag of the pages (finger up = next, down = previous).
    private(set) var feedDragY: CGFloat = 0
    /// One feed page — the player's height (set by the gesture).
    private(set) var pageHeight: CGFloat = UIScreen.size.height
    /// The slide to the next page is animating; drags wait for it.
    private(set) var feedCommitting = false
    /// The track the feed is centred on when it's ahead of playback (just
    /// landed; the player hasn't switched yet). nil = the playing track.
    private(set) var anchorOverride: MediaID?
    /// A finger is on the stage right now (set by drags, cleared on release).
    @ObservationIgnored private var feedDragActive = false
    @ObservationIgnored private var overrideGeneration = 0

    /// The centre page's track.
    func feedAnchor(current: MediaID?) -> MediaID? { anchorOverride ?? current }

    func dragFeed(_ translation: CGFloat, height: CGFloat) {
        guard !feedCommitting else { return }
        feedDragActive = true
        pageHeight = height
        feedDragY = translation
    }

    /// Release: past ~18% of the screen (or a quick flick) the next page
    /// slides in and that track plays; otherwise it springs back.
    func settleFeed(projected: CGFloat, height: CGFloat, controller: PlayerController) {
        feedDragActive = false
        guard !feedCommitting else { return }
        let toNext = projected < 0
        guard controller.commandProfile.isSwitchTrackEnabled, abs(projected) > height * 0.18,
              let anchor = feedAnchor(current: controller.state.currentMediaID),
              let target = controller.neighborID(of: anchor, toNext ? 1 : -1),
              target != anchor
        else {
            withAnimation(.smooth(duration: 0.3)) { feedDragY = 0 }
            return
        }
        feedCommitting = true
        pageHeight = height
        overrideGeneration += 1
        let generation = overrideGeneration
        withAnimation(.smooth(duration: 0.25), completionCriteria: .removed) {
            feedDragY = toNext ? -height : height
        } completion: { [weak self] in
            self?.land(on: target, generation: generation, controller: controller)
        }
        // Backstop: SwiftUI doesn't always deliver an animation's completion
        // (seen once — the feed then stayed "committing" and ignored every
        // swipe after). Land anyway once the slide has surely finished.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.land(on: target, generation: generation, controller: controller)
        }
    }

    /// Re-centre on the page that just slid in: it's the same view (keyed by
    /// track) landing on the same spot, so this is invisible. Runs once per
    /// swipe (completion or backstop, whichever comes first).
    private func land(on target: MediaID, generation: Int, controller: PlayerController) {
        guard feedCommitting, generation == overrideGeneration else { return }
        anchorOverride = target
        feedDragY = 0
        feedCommitting = false
        controller.skip(to: target)
        // Safety: never stay detached from playback for long.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.overrideGeneration == generation, !self.feedCommitting else { return }
            self.anchorOverride = nil
        }
    }

    /// A drag that ended without settling the feed (the gesture resolved to
    /// something else mid-way): put the pages back.
    func cancelFeedDrag() {
        feedDragActive = false
        guard !feedCommitting, feedDragY != 0 else { return }
        withAnimation(.smooth(duration: 0.3)) { feedDragY = 0 }
    }

    /// The playing track changed. Once playback reaches the track the feed
    /// landed on, follow playback again (the anchor id doesn't change, so
    /// nothing on screen does either).
    func trackDidChange(to id: MediaID?) {
        if anchorOverride != nil, anchorOverride == id { anchorOverride = nil }
        guard anchorOverride == nil, !feedCommitting, !feedDragActive, feedDragY != 0 else { return }
        feedDragY = 0
    }
}

// MARK: - Stage effect

/// Applies the feed swipe to a stage layer (the full-bleed video, or the
/// cover panel): rides the finger, one page at a time. Reading the per-frame values here keeps the drag out of the
/// player's body.
struct FeedStageEffect: ViewModifier {
    let stage: PlayerStageModel

    func body(content: Content) -> some View {
        // Read in a View body (a modifier's `body(content:)` doesn't pick up
        // observation reliably) — the content passes through untouched.
        FeedStageHost(stage: stage, content: content)
    }
}

private struct FeedStageHost<Content: View>: View {
    let stage: PlayerStageModel
    let content: Content

    var body: some View {
        content
            .offset(y: stage.feedDragY)
            // The feed has landed on the next track before playback switched:
            // this layer still shows the old one, so keep it out of sight.
            .opacity(stage.anchorOverride == nil ? 1 : 0)
    }
}

// MARK: - Observation wait

/// Suspends until `condition` holds (re-checked whenever an observed value it
/// reads changes) or `timeout` passes — no polling.
@MainActor
func waitUntil(timeout: Duration, _ condition: @escaping @MainActor @Sendable () -> Bool) async {
    if condition() { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let gate = ResumeOnce(continuation)
        observeUntil(condition, gate: gate)
        Task { @MainActor in
            try? await Task.sleep(for: timeout)
            gate.resume()
        }
    }
}

@MainActor
private func observeUntil(_ condition: @escaping @MainActor @Sendable () -> Bool, gate: ResumeOnce) {
    withObservationTracking {
        _ = condition()
    } onChange: {
        Task { @MainActor in
            guard !gate.isDone else { return }
            if condition() { gate.resume() } else { observeUntil(condition, gate: gate) }
        }
    }
}

/// Resumes its continuation exactly once (condition met or timed out).
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    var isDone: Bool { continuation == nil }
    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
