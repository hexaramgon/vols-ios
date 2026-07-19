//
//  RegularNowPlaying.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import SwiftUI

struct RegularNowPlaying: View {
    @Environment(PlayerController.self) var model
    var expanded: Bool
    var size: CGSize
    var animationNamespace: Namespace.ID
    /// Active panel (0 = main, 1 = comments). Owned by ExpandableNowPlaying so the
    /// dismiss pan gesture can drive left/right swipes between panels.
    @Binding var selectedPanel: Int
    /// Live horizontal drag offset from the pan gesture, so the panels track the finger.
    var pageDragX: CGFloat = 0
    /// Reflects whether the comments list is scrolled to the top — drives the
    /// "only dismiss from the top" behaviour in the parent's pan gesture.
    @Binding var commentsAtTop: Bool
    /// True while a dismiss drag is in progress — freezes the comments list so it
    /// doesn't rubber-band away from the rest of the player.
    var commentsScrollLocked: Bool = false
    /// When false (workspace file or comments panel) the cover doesn't glide on
    /// expand/collapse — it just fades with the rest of the player.
    var coverMatchEnabled: Bool = true
    /// Immersive video: hide the info strip and minimize the controls (compact
    /// transport only), leaving more of the video visible.
    var minimized: Bool = false

    /// Keeps the expanded content mounted through the dismiss animation so the
    /// whole view fades out together with the docking artwork (instead of
    /// snapping away) — then unmounts once the collapse has finished.
    @State private var renderContent: Bool = false
    @State private var unmountWork: DispatchWorkItem?
    /// Shared comments state: the list (in the pager) and the input bar (in the
    /// controls, morphed from the Comments button) read the same model.
    @State private var commentsModel = NowPlayingCommentsModel()
    /// Drives the album cover's settle-in entrance on expand (see artworkOrVisualizer).
    @State private var coverEntranceDone = false

    var body: some View {
        VStack(spacing: 0) {
            if renderContent {
                if model.currentFileId != nil {
                    // Workspace file → comments only. No artwork/info pager (so no
                    // cover, ABOUT strip, cart/folder, save/playlist/fx) — it's not a
                    // real track. Open straight to the comments panel.
                    NowPlayingCommentsPanel(model: commentsModel, atTop: $commentsAtTop, scrollLocked: commentsScrollLocked)
                        .padding(.top, ViewConst.safeAreaInsets.top)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity)
                        .frame(height: expandedCommentsHeight)
                        .transition(.identity)

                    PlayerControls(
                        commentsModel: commentsModel,
                        composerNamespace: animationNamespace,
                        commentsOpen: true
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .bottom))
                } else {
                    // Real track → artwork ⇄ comments pager.
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            mainPanel
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                            NowPlayingCommentsPanel(
                                model: commentsModel,
                                onClose: { withAnimation(.smooth(duration: 0.32)) { selectedPanel = 0 } },
                                atTop: $commentsAtTop,
                                scrollLocked: commentsScrollLocked
                            )
                                .padding(.top, ViewConst.safeAreaInsets.top)
                                .padding(.bottom, 6)
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                        .offset(x: -CGFloat(selectedPanel) * geo.size.width + pageDragX)
                    }
                    .frame(height: selectedPanel == 1 ? expandedCommentsHeight : mainContentHeight)
                    .transition(.identity)

                    PlayerControls(
                        onComment: {
                            withAnimation(.smooth(duration: 0.32)) {
                                selectedPanel = selectedPanel == 1 ? 0 : 1
                            }
                        },
                        commentsModel: commentsModel,
                        composerNamespace: animationNamespace,
                        commentsOpen: selectedPanel == 1,
                        minimized: minimized
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .bottom))
                }
            }
        }
        .allowsHitTesting(expanded)
        .overlay(alignment: .top) { offlineIndicator }
        .animation(.easeInOut(duration: 0.25), value: commentsModel.loadFailed)
        // Reset the slider to the artwork only when the track changes from the
        // one whose comments you opened — a plain collapse/expand keeps comments
        // where you left them.
        .onChange(of: model.state.currentMediaID?.value) { _, _ in
            if selectedPanel != 0 {
                withAnimation(.smooth(duration: 0.32)) { selectedPanel = 0 }
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            unmountWork?.cancel()
            if isExpanded {
                // Mount within the expand animation so the controls slide up and
                // the whole view fades in together (driven by the parent opacity).
                withAnimation(.playerExpandAnimation) {
                    renderContent = true
                }
            } else {
                // Keep the content mounted through the collapse so it fades out
                // with the docking artwork, then unmount once settled.
                let work = DispatchWorkItem { renderContent = false }
                unmountWork = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Animation.playerExpandAnimationDuration,
                    execute: work
                )
            }
        }
        .onAppear {
            if expanded {
                renderContent = true
            }
        }
    }
}

private extension RegularNowPlaying {
    /// Offline indicator — shown when the comments fetch got no response (same
    /// "couldn't get a response" signal the Home page uses).
    @ViewBuilder
    var offlineIndicator: some View {
        if expanded, commentsModel.loadFailed {
            HStack(spacing: 6) {
                LucideIcon(.triangleAlert, .xs)
                Text("No connection").font(.appCaptionMedium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .padding(.top, ViewConst.safeAreaInsets.top + 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    enum Const {
        static let horizontalPadding: CGFloat = 32
    }

    /// Artwork square dimension (same as before).
    var artworkSize: CGFloat {
        size.width - Const.horizontalPadding * 2
    }

    /// Gap below the artwork before the info strip.
    var artworkVerticalPadding: CGFloat {
        size.height < 700 ? 8 : 16
    }

    /// Info-strip thumbnail height — mirrors `NowPlayingInfoStrip.thumbSize`
    /// (the strip is sized to its square thumbnail).
    var infoStripHeight: CGFloat {
        round(size.width * 0.3)
    }

    /// Top inset above the artwork. Kept tight (the cover was widened via a
    /// smaller `horizontalPadding`, and this shrank by the same amount) so the
    /// artwork grows *upward* into this space without moving anything below it —
    /// `mainContentHeight` is unchanged.
    var artworkTopInset: CGFloat {
        ViewConst.safeAreaInsets.top + (size.height < 700 ? 2 : 24)
    }

    /// Natural height of the main panel: top inset + artwork + the gap +
    /// the info strip. The pager hugs this so the controls fill whatever's left
    /// instead of leaving a fixed gap in the middle.
    var mainContentHeight: CGFloat {
        artworkTopInset + artworkSize + artworkVerticalPadding + infoStripHeight
    }

    /// When comments are open the box grows to take the controls' empty space,
    /// reserving just enough for the (compacted) transport + input row at the
    /// bottom. Uses the full screen height (the player ignores the safe area, so
    /// `size` here is only the safe-area box). Never shrinks below the normal box.
    var expandedCommentsHeight: CGFloat {
        max(mainContentHeight, UIScreen.size.height - 320)
    }


    var isVideo: Bool {
        if case .videoPlayer = model.display.artwork { return true }
        return false
    }

    /// Availability lives on the model (shared with the full-bleed layer in
    /// ExpandableNowPlaying).
    var canShowVisualizer: Bool {
        model.visualizerAvailable
    }

    var visualizerToggleButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { model.showVisualizer.toggle() }
        } label: {
            LucideIcon(.sparkles, size: 18)
                .foregroundStyle(.white.opacity(model.showVisualizer ? 1 : 0.85))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(model.showVisualizer ? 0.35 : 0.12)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var artworkOrVisualizer: some View {
        if isVideo, model.isPortraitVideo {
            // Portrait video plays full-bleed behind everything (see
            // ExpandableNowPlaying). Keep a clear, same-sized matched-geometry frame
            // here so the layout and the expand/collapse glide stay intact without
            // double-rendering the video.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: artworkSize)
                .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: animationNamespace, isSource: coverMatchEnabled && expanded)
        } else if isVideo {
            // Landscape/square video uses the full screen width (its native ratio is
            // preserved, centered) so it isn't boxed into the square.
            artwork(model.display.artwork)
                .frame(maxWidth: .infinity)
                .frame(height: artworkSize)
                .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: animationNamespace, isSource: coverMatchEnabled && expanded)
        } else if model.display.isVideoTrack {
            // Video track whose AVPlayer hasn't spun up yet: show a loading state
            // rather than flashing the album cover; the video takes over once ready.
            videoLoadingPlaceholder
        } else if model.showVisualizer, model.visualizerAvailable {
            // Fullscreen visualizer renders full-bleed behind everything (see
            // ExpandableNowPlaying). Keep a clear, same-sized matched-geometry
            // frame here — like portrait video — so the layout and the
            // expand/collapse glide stay intact.
            Color.clear
                .frame(width: artworkSize, height: artworkSize)
                .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: animationNamespace, isSource: coverMatchEnabled && expanded)
                .frame(maxWidth: .infinity)
        } else {
            // Album cover — a centered square (matched-geometry on the square so the
            // expand/collapse glide to the mini-player stays clean). The inner cover
            // cross-fades when the track changes (next/previous) while the outer
            // matched-geometry frame stays stable for the expand glide. The glide is
            // skipped (just a fade) when there's no cover to glide to — see
            // `coverMatchEnabled`.
            ZStack {
                artwork(model.display.albumArtwork)
                    .frame(width: artworkSize, height: artworkSize)
                    .id(model.display)
                    .transition(.opacity)
            }
            .frame(width: artworkSize, height: artworkSize)
            .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: animationNamespace, isSource: coverMatchEnabled && expanded)
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.3), value: model.display)
            // Entrance: the cover used to arrive at full presence on the first
            // frame of the expansion, ahead of the card. Now it settles in a
            // beat later with a gentle scale, landing as the card finishes.
            .scaleEffect(coverEntranceDone ? 1 : 0.92)
            .opacity(coverEntranceDone ? 1 : 0)
            .onAppear {
                withAnimation(.smooth(duration: 0.4).delay(0.12)) { coverEntranceDone = true }
            }
            .onDisappear { coverEntranceDone = false }
        }
    }

    /// Loading state for a video track while its player spins up — just a spinner
    /// over a transparent area, framed like the video so the matched-geometry glide
    /// and the swap to the video stay seamless.
    var videoLoadingPlaceholder: some View {
        ProgressView()
            .tint(.white)
            .frame(maxWidth: .infinity)
            .frame(height: artworkSize)
            .matchedGeometryEffect(id: PlayerMatchedGeometry.artwork, in: animationNamespace, isSource: coverMatchEnabled && expanded)
    }

    @ViewBuilder
    func artwork(_ art: Artwork) -> some View {
        ArtworkView(
            art,
            cornerRadius: expanded ? 10 : 7,
            background: Color(.palette.playerCard.artworkBackground),
            videoAspectFit: true
        )
        // Static shadow — the cover doesn't resize or change on play/pause for now.
        .shadow(
            color: Color(.sRGBLinear, white: 0, opacity: 0.33),
            radius: 8,
            y: 10
        )
    }

    /// Artwork/visualizer (with the like/save/comment row) + the info strip.
    /// Crossfaded with the comments panel via the comment button.
    var mainPanel: some View {
        // spacing 0 so the panel's height is exactly artwork + the explicit
        // bottom padding + info strip (keeps `mainContentHeight` accurate).
        VStack(spacing: 0) {
            artworkOrVisualizer
                .overlay(alignment: .bottomTrailing) {
                    if canShowVisualizer {
                        visualizerToggleButton
                            // Inside the centered square's bottom-right corner
                            // (the square is inset `horizontalPadding` per side).
                            .padding(.trailing, Const.horizontalPadding + 10)
                            .padding(.bottom, 10)
                            // Hides with the rest of the controls in immersive
                            // mode (tap anywhere restores them).
                            .opacity(minimized ? 0 : 1)
                            .allowsHitTesting(!minimized)
                    }
                }
                .padding(.bottom, artworkVerticalPadding)

            NowPlayingInfoStrip()
                // Align the credits/About + buttons with the title, scrubber and the
                // rest of the player content (same inset everywhere).
                .padding(.horizontal, ViewConst.playerCardPaddings)
                // Hidden in minimized (immersive) mode.
                .opacity(minimized ? 0 : 1)
        }
        // A little below the safe-area edge so the cover doesn't hug the notch and
        // the stack reads more vertically centred (kept in sync with mainContentHeight).
        .padding(.top, artworkTopInset)
    }

}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    RegularNowPlaying(
        expanded: true,
        size: UIScreen.size,
        animationNamespace: Namespace().wrappedValue,
        selectedPanel: .constant(0),
        commentsAtTop: .constant(true)
    )
    .onAppear {
        playerController.mediaState = dependencies.mediaState
        playerController.player = dependencies.mediaPlayer
    }
    .background {
        ColorfulBackground(
            colors: playerController.colors.map { Color($0) }
        )
        .overlay(Color(UIColor(white: 0.4, alpha: 0.5)))
    }
    .ignoresSafeArea()
    .environment(playerController)
}
