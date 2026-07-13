//
//  ExpandableNowPlaying.swift
//  Volspire
//
//

import AVFoundation
import DesignSystem
import SwiftUI
import Visualizer

enum PlayerMatchedGeometry {
    case artwork
    case backgroundView
}

struct ExpandableNowPlaying: View {
    @Binding var show: Bool
    @Binding var expanded: Bool
    var collapsedFrame: CGRect
    @Environment(PlayerController.self) var model
    @State private var offsetY: CGFloat = 0.0
    @State private var needRestoreProgressOnActive: Bool = false
    @State private var windowProgress: CGFloat = 0.0
    @State private var progressTrackState: CGFloat = 0.0
    @State private var expandProgress: CGFloat = 0.0
    /// Which expanded panel is showing (0 = main, 1 = comments). Lifted here so the
    /// dismiss pan gesture can also drive left/right panel swipes.
    @State private var selectedPanel: Int = 0
    /// Axis the current pan locked onto, so a horizontal swipe changes panels and a
    /// vertical drag dismisses — without one bleeding into the other.
    @State private var gestureAxis: Axis? = nil
    /// Live horizontal drag offset so the panels slide under the finger.
    @State private var pageDragX: CGFloat = 0
    /// Whether the visible comments list is scrolled to the top — when comments are
    /// showing, a downward drag only dismisses from the top (otherwise it scrolls).
    @State private var commentsAtTop: Bool = true
    /// Set at the start of a vertical drag: true when this drag is allowed to drive
    /// the dismiss (artwork showing, or comments pinned to the top), false when it
    /// should be left to the comments list to scroll.
    @State private var dismissArmed: Bool = false
    /// Translation already accumulated when the axis locked — subtracted from the
    /// dismiss offset so the player follows the finger from 0 instead of snapping
    /// down by the ~10pt dead zone the moment the lock trips.
    @State private var dragBaselineY: CGFloat = 0
    /// Immersive mode for full-bleed content (portrait video / visualizer): a tap
    /// on empty space toggles the controls — hidden (title + info strip + action
    /// row gone, compact transport kept) for a cleaner full screen, tap again to
    /// bring them back. No auto-hide timer; it's the user's explicit choice.
    @State private var controlsMinimized = false
    /// Settings → "Low Power Visualizer": renders the visualizer at the lean
    /// 1.25× profile. Live — flipping it while watching rebuilds on the spot.
    @AppStorage(SettingsKeys.visualizerLowPower) private var visualizerLowPower = false
    @Namespace private var animationNamespace

    var body: some View {
        expandableNowPlaying
            .onChange(of: expanded) {
                if expanded {
                    // A workspace file only has comments — open straight to it.
                    if model.currentFileId != nil { selectedPanel = 1 }
                    stacked(progress: 1, withAnimation: true)
                }
            }
            // Lock to the comments panel for files (reset to artwork for real tracks).
            .onChange(of: model.currentFileId) { _, fileId in
                selectedPanel = fileId != nil ? 1 : 0
            }
            // Leaving immersive eligibility (comments open, collapse, non-video
            // track) always restores the controls; entering starts with them shown.
            .onChange(of: immersiveEligible) { _, eligible in
                if !eligible { controlsMinimized = false }
            }
            .onPreferenceChange(NowPlayingExpandProgressPreferenceKey.self) { [$expandProgress] value in
                $expandProgress.wrappedValue = value
            }
    }
}

private extension ExpandableNowPlaying {
    var isFullyExpanded: Bool {
        expandProgress >= 1
    }

    var isFullyCollapsed: Bool {
        expandProgress.isZero
    }

    /// 0 on the artwork panel → 1 on the comments panel, tracking the live swipe so
    /// the comments blur fades in/out under the finger.
    var commentsProgress: Double {
        let w = UIScreen.size.width
        guard w > 0 else { return Double(selectedPanel) }
        let p = CGFloat(selectedPanel) - pageDragX / w
        return Double(min(max(p, 0), 1))
    }

    /// Full-bleed portrait video + legibility scrims + a comments blur.
    func portraitVideoBackdrop(avPlayer: AVPlayer, minimized: Bool) -> some View {
        immersiveBackdrop(minimized: minimized) {
            PlayerVideoView(player: avPlayer, gravity: .resizeAspectFill)
        }
    }

    /// Full-bleed immersive content (portrait video / visualizer) + legibility
    /// scrims + a comments blur.
    /// In `minimized` mode the big frosted section crossfades to a small, subtle
    /// bottom scrim (just enough to keep the compact transport legible).
    /// NOTE: nothing in here uses `.ignoresSafeArea()` — the callers pin this
    /// backdrop to a fixed `UIScreen.size` frame, so children fill the screen by
    /// proposal alone. Safe-area expansion is POSITIONAL: it re-resolves as the
    /// player card is dragged down (the top inset drains over the first ~59pt of
    /// drag), which changed the video's bounds mid-gesture and made the
    /// aspect-fill crop visibly shift/jump. Fixed proposal → fixed crop.
    func immersiveBackdrop(minimized: Bool, @ViewBuilder content: () -> some View) -> some View {
        ZStack {
            content()
            // Top scrim (status bar / offline pill) — full-height gradient using
            // stop locations so it always reaches the screen edges (a fixed-height
            // frame can overflow on shorter devices and expose the background).
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.5), location: 0),
                    .init(color: .clear, location: 0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Bottom section behind the title, scrubber and transport — a frosted
            // (blurred) + darkened layer over the bottom of the video. Framed to
            // just the bottom 40% of the screen: the material re-blurs its whole
            // region every video frame, so the frame IS the blur cost — it was
            // full-screen originally (stuttered on minimize/restore), then 60%.
            // The fade-in now starts at 60% down (was 40%) with the gradient/mask
            // stops remapped to match the old rendering below that point.
            // Bottom-aligned inside a full-screen flexible frame so it always
            // reaches the very bottom edge. Fades via `.opacity` and MUST stay
            // mounted: a backdrop blur can't fade during a removal transition,
            // so unmounting blinks it out instead of cross-fading.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.53), location: 0),
                            .init(color: .black.opacity(0.85), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.3),
                            .init(color: .black, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .environment(\.colorScheme, .dark)
                .opacity(minimized ? 0 : 1)
                .frame(height: UIScreen.size.height * 0.4)
                .frame(maxHeight: .infinity, alignment: .bottom)
            // Minimized: a small, subtle dark scrim across just the bottom, so the
            // compact transport stays legible without the full frost.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.72),
                    .init(color: .black.opacity(0.45), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(minimized ? 1 : 0)
            // Blur the video while the comments panel is up so the list stays
            // readable. Stays mounted (opacity-driven) for the same reason as
            // the frost above — an unmounting material blinks out instead of
            // fading.
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(commentsProgress)
        }
    }

    /// Whether the immersive auto-hide applies right now: full-bleed content
    /// (portrait video or the visualizer), expanded, on the artwork panel
    /// (never while reading comments).
    var immersiveEligible: Bool {
        expanded && (model.isPortraitVideo || (model.showVisualizer && model.visualizerAvailable)) && selectedPanel == 0
    }

    /// A tap on empty space toggles the controls (immersive video/visualizer only)
    /// — tap to hide, tap again to bring them back. Taps on actual controls are
    /// consumed by them and never reach this.
    func onPlayerTap() {
        guard immersiveEligible else { return }
        withAnimation(.easeInOut(duration: 0.3)) { controlsMinimized.toggle() }
    }

    var expandableNowPlaying: some View {
        GeometryReader {
            let size = $0.size
            ZStack(alignment: .top) {
                NowPlayingBackground(
                    colors: model.colors.map { Color($0) },
                    expanded: expanded,
                    isFullExpanded: isFullyExpanded
                )
                // Portrait video → fill the whole player TikTok/Reels-style, behind
                // the controls. Scrims keep the top (status bar) and bottom (transport)
                // legible; a blur fades in as the comments panel slides over it.
                if model.isPortraitVideo, let avPlayer = model.videoAVPlayer {
                    portraitVideoBackdrop(avPlayer: avPlayer, minimized: controlsMinimized)
                        // Pinned to a constant full-screen size — NOT maxWidth/maxHeight,
                        // and no safe-area participation anywhere inside (see
                        // immersiveBackdrop). Flexible or safe-area-expanded bounds
                        // change as the card is dragged/collapsed, and any bounds
                        // change re-crops the aspect-fill video mid-gesture. Fixed
                        // bounds → the video only fades and slides, never re-fits.
                        .frame(width: UIScreen.size.width, height: UIScreen.size.height)
                        .clipShape(.rect(cornerRadius: isFullyExpanded ? 0 : UIScreen.deviceCornerRadius))
                        // The radius flips the moment a drag starts (progress < 1) —
                        // ease it in so full-bleed corners don't pop.
                        .animation(.easeOut(duration: 0.18), value: isFullyExpanded)
                        .opacity(expanded ? 1 : 0)
                        .animation(.playerExpandAnimation, value: expanded)
                        .allowsHitTesting(false)
                }
                // Fullscreen visualizer → same full-bleed treatment as portrait
                // video: behind the controls, with the identical scrims,
                // comments blur, and immersive minimize. Mounted only while
                // expanded so it costs nothing when docked.
                if expanded, model.showVisualizer, model.visualizerAvailable {
                    immersiveBackdrop(minimized: controlsMinimized) {
                        // Brightness/saturation mute ≈ the web player's dark
                        // vignette, applied in the composite shader for free.
                        MetalVisualizer(
                            audioTap: model.visualizerTap,
                            quality: visualizerLowPower ? .lowPower : .standard,
                            brightness: 0.75,
                            saturation: 0.85
                        )
                    }
                    // Same fixed-size pin as the portrait video: immersiveBackdrop's
                    // children no longer ignore the safe area, so full-bleed comes
                    // from this frame.
                    .frame(width: UIScreen.size.width, height: UIScreen.size.height)
                    .clipShape(.rect(cornerRadius: isFullyExpanded ? 0 : UIScreen.deviceCornerRadius))
                    // Same corner ease as the portrait video above.
                    .animation(.easeOut(duration: 0.18), value: isFullyExpanded)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
                CompactNowPlaying(
                    expanded: $expanded,
                    coverMatchEnabled: coverGlideEnabled,
                    animationNamespace: animationNamespace
                )
                .opacity(expanded ? 0 : 1)

                RegularNowPlaying(
                    expanded: expanded,
                    size: size,
                    animationNamespace: animationNamespace,
                    selectedPanel: $selectedPanel,
                    pageDragX: pageDragX,
                    commentsAtTop: $commentsAtTop,
                    commentsScrollLocked: dismissArmed && offsetY > 0,
                    coverMatchEnabled: coverGlideEnabled,
                    minimized: controlsMinimized
                )
                .opacity(expanded ? 1 : 0)
                ProgressTracker(progress: progressTrackState)
            }
            // Tap on empty space to toggle the controls in immersive video mode.
            // NOTE: deliberately NO `.contentShape` here. The expanded player is
            // fully covered by hit-testable layers (NowPlayingBackground at
            // minimum), so the tap lands everywhere anyway. A Rectangle
            // contentShape spans the ZStack's *bounds* — and the expanded
            // content's fixed heights overflow the collapsed 56pt frame down
            // over the tab bar (ZStacks size to their largest child; overflow
            // isn't clipped), turning it into an invisible tap-catcher that
            // made the tab bar unresponsive after dismissing the player.
            .onTapGesture { onPlayerTap() }
            .frame(height: expanded ? nil : ViewConst.compactNowPlayingHeight, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, insets.bottom)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .offset(y: offsetY)
            .gesture(
                PanGesture(
                    // Recognize alongside the comments scroll view so a drag that
                    // starts inside the list can still drive the dismiss.
                    simultaneous: true,
                    onChange: { handleGestureChange(value: $0, viewSize: size) },
                    onEnd: { handleGestureEnd(value: $0, viewSize: size) }
                )
            )
            .ignoresSafeArea()
        }
    }

    /// Whether the comments scroll view is the visible content (workspace file, or a
    /// real track with the comments panel open) — when it is, a downward drag should
    /// only dismiss from the very top.
    private var commentsShowing: Bool {
        model.currentFileId != nil || selectedPanel == 1
    }

    /// The cover used to GLIDE between the expanded artwork and the mini-player
    /// thumbnail via matched geometry on expand/collapse. Disabled: the fly-to-
    /// the-corner read as the cover "animating away to the left" on dismiss,
    /// while full-bleed videos and the visualizer just fade in place — now the
    /// cover stays in frame and fades with the player like everything else.
    /// (The matched-geometry plumbing stays wired; flip this back to
    /// `model.currentFileId == nil && selectedPanel == 0` to restore the glide.)
    private var coverGlideEnabled: Bool {
        false
    }

    func handleGestureChange(value: PanGesture.Value, viewSize: CGSize) {
        guard expanded else { return }
        let dx = value.translation.width
        let dy = value.translation.height

        // Lock the axis on the first meaningful movement so the gesture is either a
        // panel swipe (horizontal) or a dismiss (vertical), never both.
        if gestureAxis == nil, abs(dx) > 10 || abs(dy) > 10 {
            gestureAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
            // Anchor the dismiss at the lock point, not the touch-down point —
            // otherwise the dead-zone translation lands in one frame and the
            // player visibly snaps down as the drag starts.
            dragBaselineY = dy
            // Decide up front whether this vertical drag dismisses or scrolls the
            // comments: only arm dismiss when no scrollable comments are showing, or
            // when they're pinned to the top and the drag is heading down.
            dismissArmed = !commentsShowing || (commentsAtTop && dy > 0)
            // Any drag (panel swipe or dismiss) should put the keyboard away.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        // Horizontal swipe: slide the panels live under the finger, with a little
        // resistance when there's no panel to slide to.
        if gestureAxis == .horizontal {
            // Files are comments-only — no artwork panel to swipe to.
            if model.currentFileId != nil { return }
            var x = dx
            if (selectedPanel == 0 && x > 0) || (selectedPanel == 1 && x < 0) {
                x *= 0.25
            }
            pageDragX = x
            return
        }

        // Vertical drag that isn't a dismiss → leave it to the comments list to scroll.
        guard dismissArmed else { return }

        let translation = max(dy - dragBaselineY, 0)
        offsetY = translation
        windowProgress = max(min(translation / viewSize.height, 1), 0)
        stacked(progress: 1 - windowProgress, withAnimation: false)
    }

    func handleGestureEnd(value: PanGesture.Value, viewSize: CGSize) {
        guard expanded else { return }
        let axis = gestureAxis
        let armed = dismissArmed
        let baseline = dragBaselineY
        gestureAxis = nil
        dismissArmed = false
        dragBaselineY = 0

        // Horizontal swipe → settle to the nearest panel (with a slide).
        if axis == .horizontal {
            if model.currentFileId != nil { withAnimation(.smooth(duration: 0.32)) { pageDragX = 0 }; return }
            let projected = value.translation.width + value.velocity.width / 6
            withAnimation(.smooth(duration: 0.32)) {
                if projected < -viewSize.width * 0.2 {
                    selectedPanel = min(selectedPanel + 1, 1)
                } else if projected > viewSize.width * 0.2 {
                    selectedPanel = max(selectedPanel - 1, 0)
                }
                pageDragX = 0
            }
            return
        }

        // The drag was a comments scroll, not a dismiss — nothing to settle.
        guard armed else { return }

        // Vertical drag → dismiss (or settle back).
        let translation = max(value.translation.height - baseline, 0)
        let velocity = value.velocity.height / 5
        withAnimation(.playerExpandAnimation) {
            if (translation + velocity) > (viewSize.height * 0.3) {
                expanded = false
                resetStackedWithAnimation()
            } else {
                stacked(progress: 1, withAnimation: true)
            }
            offsetY = 0
        }
    }

    func stacked(progress: CGFloat, withAnimation: Bool) {
        if withAnimation {
            SwiftUI.withAnimation(.playerExpandAnimation) {
                progressTrackState = progress
            }
        } else {
            progressTrackState = progress
        }
    }

    func resetStackedWithAnimation() {
        withAnimation(.playerExpandAnimation) {
            progressTrackState = 0
        }
    }

    var insets: EdgeInsets {
        if expanded {
            return .init(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        return .init(
            top: 0,
            leading: collapsedFrame.minX,
            bottom: UIScreen.size.height - collapsedFrame.maxY,
            trailing: UIScreen.size.width - collapsedFrame.maxX
        )
    }
}

extension Animation {
    static let playerExpandAnimationDuration: TimeInterval = 0.3
    static var playerExpandAnimation: Animation {
        .smooth(duration: playerExpandAnimationDuration, extraBounce: 0)
    }
}

private struct ProgressTracker: View, @preconcurrency Animatable {
    var progress: CGFloat = 0

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

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    OverlaidRootView()
        .environment(playerController)
        .environment(dependencies)
}
