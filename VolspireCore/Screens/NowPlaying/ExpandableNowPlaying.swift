//
//  ExpandableNowPlaying.swift
//  Volspire
//
//

import AVFoundation
import DesignSystem
import SwiftUI

enum PlayerMatchedGeometry {
    case artwork
    case backgroundView
}

struct ExpandableNowPlaying: View {
    @Binding var show: Bool
    @Binding var expanded: Bool
    var collapsedFrame: CGRect
    @Environment(PlayerController.self) var model
    @Environment(\.scenePhase) private var scenePhase
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
    /// Immersive mode for a full-bleed portrait video: after a few seconds the
    /// controls minimize (title + info strip + action row hidden, compact transport
    /// kept) for a cleaner full-screen video; a tap restores them (and restarts the
    /// timer).
    @State private var controlsMinimized = false
    @State private var hideControlsWork: DispatchWorkItem?
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
            // Immersive auto-hide: start the timer when eligible (portrait video,
            // expanded, on the artwork panel); always show the controls otherwise.
            .onChange(of: immersiveEligible) { _, eligible in
                if eligible {
                    scheduleHideControls()
                } else {
                    hideControlsWork?.cancel()
                    controlsMinimized = false
                }
            }
            // Returning from another app (or the lock screen): bring the controls
            // back to normal size and re-arm the 5s auto-hide, rather than coming
            // back to a minimized player. (Background timers don't fire while
            // suspended, so without this it'd stay hidden.)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, immersiveEligible { revealControls() }
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
    /// In `minimized` mode the big frosted section crossfades to a small, subtle
    /// bottom scrim (just enough to keep the compact transport legible).
    func portraitVideoBackdrop(avPlayer: AVPlayer, minimized: Bool) -> some View {
        ZStack {
            PlayerVideoView(player: avPlayer, gravity: .resizeAspectFill)
                .ignoresSafeArea()
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
            .ignoresSafeArea()
            // Bottom section behind the title, scrubber and transport — a frosted
            // (blurred) + darkened layer that fades in from ~40% down. Full-height
            // and masked by stop locations (no fixed frame), so it always reaches
            // the very bottom edge without exposing the background. Fades out when
            // the controls minimize.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.45), .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.4),
                            .init(color: .black, location: 0.72),
                            .init(color: .black, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .environment(\.colorScheme, .dark)
                .opacity(minimized ? 0 : 1)
                .ignoresSafeArea()
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
            .ignoresSafeArea()
            // Blur the video while the comments panel is up so the list stays readable.
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(commentsProgress)
                .ignoresSafeArea()
        }
    }

    /// Whether the immersive auto-hide applies right now: a full-bleed portrait
    /// video, expanded, on the artwork panel (never while reading comments).
    var immersiveEligible: Bool {
        expanded && model.isPortraitVideo && selectedPanel == 0
    }

    /// Minimize the controls after 5s (only while eligible).
    func scheduleHideControls() {
        hideControlsWork?.cancel()
        guard immersiveEligible else { return }
        let work = DispatchWorkItem {
            guard immersiveEligible else { return }
            withAnimation(.easeInOut(duration: 0.35)) { controlsMinimized = true }
        }
        hideControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Restore the full controls and restart the auto-minimize timer.
    func revealControls() {
        withAnimation(.easeInOut(duration: 0.25)) { controlsMinimized = false }
        scheduleHideControls()
    }

    /// A tap on empty space restores the controls (immersive video only).
    func onPlayerTap() {
        guard immersiveEligible else { return }
        revealControls()
    }

    /// Any tap (incl. a button press) restarts the auto-minimize timer — but only
    /// while the controls are still showing, so interacting with them doesn't let
    /// them minimize out from under you. Once already minimized, a button press
    /// leaves it minimized (the empty-space tap is what restores).
    func onAnyTap() {
        guard immersiveEligible, !controlsMinimized else { return }
        scheduleHideControls()
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(.rect(cornerRadius: isFullyExpanded ? 0 : UIScreen.deviceCornerRadius))
                        .opacity(expanded ? 1 : 0)
                        .animation(.playerExpandAnimation, value: expanded)
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
            // Tap on empty space to bring the controls back in immersive video mode…
            .contentShape(Rectangle())
            .onTapGesture { onPlayerTap() }
            // …and any tap (including button presses) keeps them alive by restarting
            // the auto-minimize timer while they're showing.
            .simultaneousGesture(TapGesture().onEnded { onAnyTap() })
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

    /// Whether the cover's expand/collapse glide should be the active matched-geometry
    /// source. Only when there's a cover (real track, not a workspace file) AND the
    /// cover panel is the one on screen — on the comments panel the cover is parked
    /// off to the side, so gliding it would drag it across the screen on collapse.
    /// Toggled via `isSource` (the modifier stays attached) so sliding between the
    /// cover and comments panels never jumps.
    private var coverGlideEnabled: Bool {
        model.currentFileId == nil && selectedPanel == 0
    }

    func handleGestureChange(value: PanGesture.Value, viewSize: CGSize) {
        guard expanded else { return }
        let dx = value.translation.width
        let dy = value.translation.height

        // Lock the axis on the first meaningful movement so the gesture is either a
        // panel swipe (horizontal) or a dismiss (vertical), never both.
        if gestureAxis == nil, abs(dx) > 10 || abs(dy) > 10 {
            gestureAxis = abs(dx) > abs(dy) ? .horizontal : .vertical
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

        let translation = max(dy, 0)
        offsetY = translation
        windowProgress = max(min(translation / viewSize.height, 1), 0)
        stacked(progress: 1 - windowProgress, withAnimation: false)
    }

    func handleGestureEnd(value: PanGesture.Value, viewSize: CGSize) {
        guard expanded else { return }
        let axis = gestureAxis
        let armed = dismissArmed
        gestureAxis = nil
        dismissArmed = false

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
        let translation = max(value.translation.height, 0)
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
