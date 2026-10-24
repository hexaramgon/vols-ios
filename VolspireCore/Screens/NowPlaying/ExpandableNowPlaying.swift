//
//  ExpandableNowPlaying.swift
//  Volspire
//
//

import AVFoundation
import DesignSystem
import SwiftUI
import Visualizer

struct ExpandableNowPlaying: View {
    @Binding var expanded: Bool
    var collapsedFrame: CGRect
    @Environment(PlayerController.self) var model
    /// Which expanded panel is showing (0 = main, 1 = comments). Lifted here so the
    /// dismiss pan gesture can also drive left/right panel swipes.
    @State private var selectedPanel: Int = 0
    /// Whether the visible comments list is scrolled to the top — when comments are
    /// showing, a downward drag only dismisses from the top (otherwise it scrolls).
    @State private var commentsAtTop: Bool = true
    /// The card has fully expanded (square screen corners). Written only when
    /// it flips — the progress behind it animates every frame.
    @State private var isFullyExpanded = false
    /// Per-frame gesture values, read only by the modifiers that apply them.
    @State private var drag = PlayerDragState()
    /// Full-screen mode + the feed swipe.
    @State private var stage = PlayerStageModel()
    /// Settings → "Low Power Visualizer": renders the visualizer at the lean
    /// 1.25× profile. Live — flipping it while watching rebuilds on the spot.
    @AppStorage(SettingsKeys.visualizerLowPower) private var visualizerLowPower = false
    /// The Comments button → comment input morph.
    @Namespace private var composerNamespace

    var body: some View {
        expandableNowPlaying
            .onChange(of: expanded) {
                if expanded {
                    // A workspace file opens straight onto its comments.
                    if commentsLocked { selectedPanel = 1 }
                    stage.playerWillExpand()
                    withAnimation(.playerExpandAnimation) { drag.expandTrack = 1 }
                } else {
                    withAnimation(.playerExpandAnimation) { drag.expandTrack = 0 }
                }
            }
            // Workspace files live on the comments panel (locked there);
            // stepping from a file back to a track returns to the artwork.
            .onChange(of: commentsLocked) { _, locked in
                let panel = locked ? 1 : 0
                guard selectedPanel != panel else { return }
                if expanded {
                    withAnimation(.smooth(duration: 0.32)) { selectedPanel = panel }
                } else {
                    selectedPanel = panel
                }
            }
            .onChange(of: model.state.currentMediaID?.value) {
                stage.trackDidChange(to: model.state.currentMediaID)
            }
            .onChange(of: selectedPanel) { _, panel in
                if panel == 1 { stage.commentsDidOpen() } else { stage.commentsDidClose() }
            }
            .onPreferenceChange(NowPlayingExpandProgressPreferenceKey.self) { [$isFullyExpanded] value in
                let full = value >= 1
                if $isFullyExpanded.wrappedValue != full { $isFullyExpanded.wrappedValue = full }
            }
    }
}

private extension ExpandableNowPlaying {
    /// The video's height at full screen width and its own aspect ratio
    /// (capped to the screen).
    var fittedVideoHeight: CGFloat {
        let screen = UIScreen.size
        guard let a = model.videoAspect, a.width > 0, a.height > 0 else { return screen.height }
        return min(screen.width * a.height / a.width, screen.height)
    }

    /// Full-bleed portrait video + legibility scrims + the comments blur.
    func portraitVideoBackdrop(avPlayer: AVPlayer) -> some View {
        immersiveBackdrop {
            // The clip at its true ratio, full width and pinned to the top (no
            // letterbox above it) — the same in both modes, so toggling
            // full-screen never zooms it. Fill gravity in a box of the video's
            // own ratio = no crop.
            let videoHeight = fittedVideoHeight
            PlayerVideoView(player: avPlayer, gravity: .resizeAspectFill)
                .frame(width: UIScreen.size.width, height: videoHeight)
                // Soft bottom edge: the clip fades into the backdrop over its
                // last ~36pt instead of ending on a hard line.
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: max(0, 1 - 36 / videoHeight)),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: UIScreen.size.width, height: UIScreen.size.height, alignment: .top)
        }
    }

    /// Full-bleed immersive content (portrait video / visualizer) + legibility
    /// scrims + the comments blur. In full-screen mode the bottom shade swaps
    /// for a lighter one (just enough to keep the title + scrubber legible).
    /// The always-on scrims are solid-colour gradients, not materials: a blur
    /// over playing video re-renders its whole region every frame. Only the
    /// comments blur is a material, and only while comments are open.
    /// NOTE: nothing in here uses `.ignoresSafeArea()` — the callers pin this
    /// backdrop to a fixed `UIScreen.size` frame, so children fill the screen by
    /// proposal alone. Safe-area expansion is POSITIONAL: it re-resolves as the
    /// player card is dragged down (the top inset drains over the first ~59pt of
    /// drag), which changed the video's bounds mid-gesture and made the
    /// aspect-fill crop visibly shift/jump. Fixed proposal → fixed crop.
    func immersiveBackdrop(@ViewBuilder content: () -> some View) -> some View {
        let fullScreen = stage.stageFullScreen
        return ZStack {
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
            // Bottom shade behind the title, scrubber and transport: the bottom
            // 40% of the screen, darkening toward the edge. Bottom-aligned in a
            // full-screen flexible frame so it always reaches the very bottom.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.6), location: 0.3),
                    .init(color: .black.opacity(0.88), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(fullScreen ? 0 : 1)
            .frame(height: UIScreen.size.height * 0.4)
            .frame(maxHeight: .infinity, alignment: .bottom)
            // Full-screen mode: a small, subtle shade across just the bottom.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.72),
                    .init(color: .black.opacity(0.45), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(fullScreen ? 1 : 0)
            CommentsDimLayer(drag: drag, panel: selectedPanel)
        }
    }

    /// A workspace file is playing: the player is locked to its comments
    /// (no swiping back to the artwork panel).
    var commentsLocked: Bool {
        model.currentFileId != nil
    }

    /// Full-screen mode can be toggled right now: expanded, on the artwork
    /// panel (never while reading comments) — any track.
    var fullScreenAvailable: Bool {
        expanded && selectedPanel == 0
    }

    /// Full-screen mode is on: vertical drags page tracks instead of dismissing
    /// (the two would fight); swipe-to-dismiss returns with the controls.
    var feedSwipeEnabled: Bool {
        stage.controlsMinimized && fullScreenAvailable
    }

    /// A tap on empty space toggles full-screen mode. Taps on actual controls
    /// are consumed by them and never reach this.
    func onPlayerTap() {
        guard fullScreenAvailable else { return }
        stage.toggleFullScreen()
    }

    var expandableNowPlaying: some View {
        GeometryReader {
            let size = $0.size
            ZStack(alignment: .top) {
                NowPlayingBackground(
                    colors: model.colors,
                    meshColors: model.meshColors,
                    expanded: expanded,
                    isFullExpanded: isFullyExpanded
                )
                // Portrait video → fill the whole player TikTok/Reels-style, behind
                // the controls. Scrims keep the top (status bar) and bottom (transport)
                // legible; a blur fades in as the comments panel slides over it.
                if model.isPortraitVideo, let avPlayer = model.videoAVPlayer {
                    // Layout-neutral wrapper: the backdrop is pinned to a fixed
                    // full-screen frame below, and a fixed-size ZStack child
                    // forces the COLLAPSED card that wide too (the mini player
                    // rendered past its 8pt margins whenever a video was
                    // playing). An overlay draws without contributing to layout.
                    Color.clear
                        .overlay {
                            portraitVideoBackdrop(avPlayer: avPlayer)
                                // The feed swipe drags the video itself (the
                                // controls stay put), fading as it leaves.
                                .modifier(FeedStageEffect(stage: stage))
                                // Hidden until the clip is actually playing,
                                // then fades in as the cover fades out — no
                                // half-loaded video peeking out behind it.
                                .opacity(model.videoReady ? 1 : 0)
                                .animation(.easeInOut(duration: 0.35), value: model.videoReady)
                                .fullBleedLayer(isFullyExpanded: isFullyExpanded)
                                .opacity(expanded ? 1 : 0)
                                .animation(.playerExpandAnimation, value: expanded)
                        }
                        .allowsHitTesting(false)
                }
                // Fullscreen visualizer → same full-bleed treatment as portrait
                // video: behind the controls, with the identical scrims,
                // comments blur, and full-screen mode. Mounted only while
                // expanded so it costs nothing when docked.
                if expanded, model.showVisualizer, model.visualizerAvailable {
                    // Same layout-neutral overlay wrapper as the portrait video —
                    // while the removal transition runs during a collapse, the
                    // fixed frame would otherwise widen the shrinking card.
                    Color.clear
                        .overlay {
                            immersiveBackdrop {
                                // Brightness/saturation mute ≈ the web player's dark
                                // vignette, applied in the composite shader for free.
                                MetalVisualizer(
                                    audioTap: model.visualizerTap,
                                    quality: visualizerLowPower ? .lowPower : .standard,
                                    brightness: 0.75,
                                    saturation: 0.85
                                )
                            }
                            .fullBleedLayer(isFullyExpanded: isFullyExpanded)
                        }
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                CompactNowPlaying(expanded: $expanded)
                    .opacity(expanded ? 0 : 1)

                RegularNowPlaying(
                    expanded: expanded,
                    size: size,
                    composerNamespace: composerNamespace,
                    selectedPanel: $selectedPanel,
                    commentsAtTop: $commentsAtTop,
                    drag: drag,
                    stage: stage
                )
                // The expanded player stays dark in light mode (like the web's
                // theme-dark player); the mini player themes with the app.
                // Scoped, never `.preferredColorScheme` (that hits the window).
                .alwaysDark()
                ExpandProgressTracker(drag: drag)
            }
            // Tap on empty space toggles full-screen mode.
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
            .modifier(DismissDragEffect(drag: drag))
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

    /// Whether the comments scroll view is the visible content — when it is, a
    /// downward drag should only dismiss from the very top.
    var commentsShowing: Bool {
        selectedPanel == 1
    }

    func handleGestureChange(value: PanGesture.Value, viewSize: CGSize) {
        guard expanded else { return }
        let dx = value.translation.width
        let dy = value.translation.height

        // Lock the axis on the first meaningful movement so the gesture is either a
        // panel swipe (horizontal) or a dismiss (vertical), never both.
        if drag.axis == nil, abs(dx) > 10 || abs(dy) > 10 {
            let axis: Axis = abs(dx) > abs(dy) ? .horizontal : .vertical
            drag.axis = axis
            // Anchor the dismiss at the lock point, not the touch-down point —
            // otherwise the dead-zone translation lands in one frame and the
            // player visibly snaps down as the drag starts.
            drag.baselineY = dy
            // Decide up front whether this vertical drag dismisses or scrolls the
            // comments: only arm dismiss when no scrollable comments are showing, or
            // when they're pinned to the top and the drag is heading down.
            drag.dismissArmed = !commentsShowing || (commentsAtTop && dy > 0)
            // Full-screen mode: a pull down from the top edge still dismisses.
            drag.dismissFromTop = feedSwipeEnabled && axis == .vertical && dy > 0
                && value.startLocation.y < ViewConst.safeAreaInsets.top + 160
            // Any drag (panel swipe or dismiss) should put the keyboard away.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        // Horizontal swipe: slide the panels live under the finger, with a little
        // resistance when there's no panel to slide to.
        if drag.axis == .horizontal {
            guard !commentsLocked else { return }
            var x = dx
            if (selectedPanel == 0 && x > 0) || (selectedPanel == 1 && x < 0) {
                x *= 0.25
            }
            drag.pageDragX = x
            return
        }

        // Full-screen mode: the drag pages tracks, never dismisses.
        if drag.axis == .vertical, feedSwipeEnabled, !drag.dismissFromTop {
            drag.dismissArmed = false
            stage.dragFeed(dy - drag.baselineY, height: viewSize.height)
            return
        }

        // Vertical drag that isn't a dismiss → leave it to the comments list to scroll.
        guard drag.dismissArmed else { return }

        let translation = max(dy - drag.baselineY, 0)
        drag.offsetY = translation
        drag.setCommentsScrollLocked(translation > 0)
        drag.expandTrack = 1 - max(min(translation / viewSize.height, 1), 0)
    }

    func handleGestureEnd(value: PanGesture.Value, viewSize: CGSize) {
        guard expanded else { return }
        let axis = drag.axis
        let armed = drag.dismissArmed
        let baseline = drag.baselineY
        let topDismiss = drag.dismissFromTop
        drag.resetGesture()
        drag.setCommentsScrollLocked(false)

        // Horizontal swipe → settle to the nearest panel (with a slide).
        if axis == .horizontal {
            guard !commentsLocked else { return }
            let projected = value.translation.width + value.velocity.width / 6
            withAnimation(.smooth(duration: 0.32)) {
                if projected < -viewSize.width * 0.2 {
                    selectedPanel = min(selectedPanel + 1, 1)
                } else if projected > viewSize.width * 0.2 {
                    selectedPanel = max(selectedPanel - 1, 0)
                }
                drag.pageDragX = 0
            }
            return
        }

        if axis == .vertical, feedSwipeEnabled, !topDismiss {
            let projected = (value.translation.height - baseline) + value.velocity.height / 5
            stage.settleFeed(projected: projected, height: viewSize.height, controller: model)
            return
        }
        // Any other ending must not strand a feed drag mid-screen (e.g. full
        // screen toggled off while the finger was down).
        stage.cancelFeedDrag()

        // The drag was a comments scroll, not a dismiss — nothing to settle.
        guard armed else { return }

        // Vertical drag → dismiss (or settle back).
        let translation = max(value.translation.height - baseline, 0)
        let velocity = value.velocity.height / 5
        withAnimation(.playerExpandAnimation) {
            if (translation + velocity) > (viewSize.height * 0.3) {
                expanded = false
                drag.expandTrack = 0
            } else {
                drag.expandTrack = 1
            }
            drag.offsetY = 0
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

private extension View {
    /// A full-bleed layer (portrait video, visualizer) pinned to a constant
    /// full-screen size — NOT maxWidth/maxHeight, and no safe-area
    /// participation (see `immersiveBackdrop`): flexible bounds change as the
    /// card is dragged/collapsed and re-crop aspect-fill video mid-gesture.
    /// Rounded to the device corners until the card has fully expanded; the
    /// radius flips the moment a drag starts, so ease it rather than pop.
    func fullBleedLayer(isFullyExpanded: Bool) -> some View {
        frame(width: UIScreen.size.width, height: UIScreen.size.height)
            .clipShape(.rect(cornerRadius: isFullyExpanded ? 0 : UIScreen.deviceCornerRadius))
            .animation(.easeOut(duration: 0.18), value: isFullyExpanded)
    }
}

extension Animation {
    /// The player's expand / collapse curve.
    static let playerExpandAnimation: Animation = .smooth(duration: 0.3, extraBounce: 0)
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    OverlaidRootView()
        .environment(playerController)
        .environment(dependencies)
}
