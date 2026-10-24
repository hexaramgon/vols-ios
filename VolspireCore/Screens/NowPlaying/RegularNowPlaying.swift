//
//  RegularNowPlaying.swift
//  Volspire
//
//

import DesignSystem
import MediaLibrary
import Kingfisher
import SwiftUI

struct RegularNowPlaying: View {
    @Environment(PlayerController.self) var model
    var expanded: Bool
    var size: CGSize
    /// The Comments button → comment input morph.
    var composerNamespace: Namespace.ID
    /// Active panel (0 = main, 1 = comments). Owned by ExpandableNowPlaying so the
    /// dismiss pan gesture can drive left/right swipes between panels.
    @Binding var selectedPanel: Int
    /// Reflects whether the comments list is scrolled to the top — drives the
    /// "only dismiss from the top" behaviour in the parent's pan gesture.
    @Binding var commentsAtTop: Bool
    /// Live gesture values (pager offset, comments scroll lock).
    let drag: PlayerDragState
    /// Full-screen mode + the feed swipe.
    let stage: PlayerStageModel

    /// Keeps the expanded content mounted through the dismiss animation so the
    /// whole view fades out together with the docking artwork (instead of
    /// snapping away) — then unmounts once the collapse has finished.
    @State private var renderContent: Bool = false
    /// The expanded content's own fade (in on expand, out on collapse) — owned
    /// here so the unmount can wait for the fade-out to actually finish.
    @State private var contentShown: Bool = false
    /// Shared comments state: the list (in the pager) and the input bar (in the
    /// controls, morphed from the Comments button) read the same model.
    @State private var commentsModel = NowPlayingCommentsModel()
    /// Drives the album cover's settle-in entrance on expand (see artworkOrVisualizer).
    @State private var coverEntranceDone = false

    var body: some View {
        VStack(spacing: 0) {
            if renderContent {
                // ONE tree for tracks and workspace files alike: artwork ⇄ comments
                // pager, then the controls. Files used to render a completely
                // different branch (comments-only, `commentsOpen: true` hardcoded),
                // so stepping between a folder's track and its file swapped the
                // whole subtree — PlayerControls lost its identity and its measured
                // transport height, the bottom bar jumped between the action row and
                // the composer, and the pager fought the forced panel. What a file
                // lacks is CONTENT (no info strip), not a different player.
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        mainPanel
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                        NowPlayingCommentsPanel(
                            model: commentsModel,
                            onClose: { withAnimation(.smooth(duration: 0.32)) { selectedPanel = 0 } },
                            atTop: $commentsAtTop,
                            scrollLocked: drag.commentsScrollLocked,
                            isActive: selectedPanel == 1
                        )
                            .padding(.top, ViewConst.safeAreaInsets.top)
                            .padding(.bottom, 6)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .modifier(PagerOffsetEffect(drag: drag, panel: selectedPanel, width: geo.size.width))
                }
                .frame(height: selectedPanel == 1 ? expandedCommentsHeight : mainContentHeight)
                .transition(.identity)

                PlayerControls(
                    onComment: {
                        // Locked to comments while a workspace file plays.
                        guard model.currentFileId == nil else { return }
                        withAnimation(.smooth(duration: 0.32)) {
                            selectedPanel = selectedPanel == 1 ? 0 : 1
                        }
                    },
                    commentsModel: commentsModel,
                    composerNamespace: composerNamespace,
                    commentsOpen: selectedPanel == 1,
                    minimized: minimized,
                    onTitleDrop: { stage.fullScreenTitleDrop = $0 }
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .bottom))
                    // Above the stage: the feed's next cover slides up from
                    // below and must pass under the title + scrubber.
                    .zIndex(1)
            }
        }
        // Grabber: only in full-screen mode, where a pull down from the top
        // is the one drag that dismisses (others page tracks) — it marks
        // that spot.
        .overlay(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(width: 36, height: 5)
                .padding(.top, ViewConst.safeAreaInsets.top + 6)
                .opacity(stageFullScreen ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: stageFullScreen)
                .allowsHitTesting(false)
        }
        .opacity(contentShown ? 1 : 0)
        .allowsHitTesting(expanded)
        // Text shadows only while a video plays — elsewhere the type sits on
        // the calm album tint and needs no halo.
        .environment(\.playerOverlayShadowsEnabled, model.display.isVideoTrack)
        .overlay(alignment: .top) { offlineIndicator }
        .animation(.easeInOut(duration: 0.25), value: commentsModel.loadFailed)
        // Reset the slider to the artwork only when the track changes from the
        // one whose comments you opened — a plain collapse/expand keeps comments
        // where you left them.
        .onChange(of: model.state.currentMediaID?.value) { _, _ in
            // Workspace files stay on their comments (locked there).
            if selectedPanel != 0, model.currentFileId == nil {
                withAnimation(.smooth(duration: 0.32)) { selectedPanel = 0 }
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                // Mount within the expand animation so the controls slide up and
                // the whole view fades in together.
                withAnimation(.playerExpandAnimation) {
                    renderContent = true
                    contentShown = true
                }
            } else {
                // Keep the content mounted through the collapse so it fades out
                // with the card, then unmount when that fade has finished.
                withAnimation(.playerExpandAnimation) {
                    contentShown = false
                } completion: {
                    if !expanded {
                        renderContent = false
                        // The cover's entrance replays on the next expansion.
                        coverEntranceDone = false
                    }
                }
            }
        }
        .onAppear {
            if expanded {
                renderContent = true
                contentShown = true
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
            .padding(.top, ViewConst.safeAreaInsets.top + 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    enum Const {
        static let horizontalPadding: CGFloat = 32
    }

    /// Full-screen mode: the controls are tucked away.
    var minimized: Bool { stage.controlsMinimized }

    /// The stage keeps its full-screen layout (also behind comments opened
    /// from full-screen mode).
    var stageFullScreen: Bool { stage.stageFullScreen }

    /// Artwork square dimension (same as before).
    var artworkSize: CGFloat {
        size.width - Const.horizontalPadding * 2
    }

    /// Gap below the artwork before the info strip.
    var artworkVerticalPadding: CGFloat {
        size.height < 700 ? 8 : 16
    }

    /// A workspace file isn't a real track: no description, credits, playlist or
    /// workspace actions apply. The strip is hidden rather than removed, and this
    /// height is unconditional — a file and a track then lay out IDENTICALLY, so
    /// stepping between them in a folder queue moves nothing on screen.
    var isWorkspaceFile: Bool { model.currentFileId != nil }

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


    /// How far the cover drops in full-screen mode: from its usual spot to
    /// the middle of the space between the status bar and the minimized
    /// controls (title + scrubber, ~150pt above the home indicator). Full-bleed
    /// content (portrait video, the visualizer) has nothing to move.
    var fullScreenCoverOffset: CGFloat {
        if isVideo && model.isPortraitVideo { return 0 }
        if !model.display.isVideoTrack && model.showVisualizer && model.visualizerAvailable { return 0 }
        let screen = UIScreen.size.height
        let controlsTop = screen - ViewConst.safeAreaInsets.bottom - 150
        let targetCenter = (ViewConst.safeAreaInsets.top + controlsTop) / 2
        // A landscape/square video's box is a full-width square here.
        let boxHeight = isVideo ? size.width : artworkSize
        let currentCenter = artworkTopInset + boxHeight / 2
        return max(targetCenter - currentCenter, 0)
    }

    /// `fullScreenCoverOffset` for an album cover (a square `artworkSize`
    /// box) — where the feed's neighbour covers sit, since that's where the
    /// stage puts them once they land.
    var albumFullScreenOffset: CGFloat {
        let controlsTop = UIScreen.size.height - ViewConst.safeAreaInsets.bottom - 150
        let targetCenter = (ViewConst.safeAreaInsets.top + controlsTop) / 2
        return max(targetCenter - (artworkTopInset + artworkSize / 2), 0)
    }

    /// `fullScreenCoverOffset` for a landscape/square video's full-width box.
    var videoFullScreenOffset: CGFloat {
        let controlsTop = UIScreen.size.height - ViewConst.safeAreaInsets.bottom - 150
        let targetCenter = (ViewConst.safeAreaInsets.top + controlsTop) / 2
        return max(targetCenter - (artworkTopInset + size.width / 2), 0)
    }

    /// How far the info strip drops in full-screen mode: exactly as far as the
    /// title glides down, so the strip (description + Save / Playlist, which
    /// stay visible) keeps the same gap above the title as in the normal layout.
    var fullScreenStripOffset: CGFloat {
        // A landscape/square video's box grows to a full-width square here,
        // which already pushes the strip down by the difference.
        let growth = isVideo && !model.isPortraitVideo ? size.width - artworkSize : 0
        return max(stage.fullScreenTitleDrop - growth, 0)
    }

    /// The video is actually on screen: a player AND a loaded clip. Until
    /// then the track lays out and draws as its cover (with a spinner) — the
    /// same cover view the feed swiped in, so nothing remounts or blinks, and
    /// a clip that never loads still shows its cover.
    var isVideo: Bool {
        guard case .videoPlayer = model.display.artwork else { return false }
        return model.videoReady
    }

    /// Availability lives on the model (shared with the full-bleed layer in
    /// ExpandableNowPlaying).
    var canShowVisualizer: Bool {
        model.visualizerAvailable
    }

    /// The web hero's View pill: a borderless glass capsule (icon-only on
    /// phones, 20pt glyph @ 0.64) showing the current view, opening a
    /// Visualizer / Video / Cover menu with a check on the active item. Video
    /// is listed but disabled — the menu only shows for audio tracks (the
    /// visualizer is unavailable on video tracks, which always play video).
    var visualizerToggleButton: some View {
        Menu {
            Button {
                withAnimation(.smooth(duration: 0.3)) { model.showVisualizer = true }
            } label: {
                viewModeLabel("Visualizer", icon: .sparkles, active: model.showVisualizer)
            }
            Button {} label: { viewModeLabel("Video", icon: .video, active: false) }
                .disabled(true)
            Button {
                withAnimation(.smooth(duration: 0.3)) { model.showVisualizer = false }
            } label: {
                viewModeLabel("Cover", icon: .image, active: !model.showVisualizer)
            }
        } label: {
            LucideIcon(model.showVisualizer ? .sparkles : .image, .lg)
                .foregroundStyle(.white.opacity(0.64))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.black.opacity(0.4), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .contentShape(Capsule())
        }
        .accessibilityLabel("View: \(model.showVisualizer ? "Visualizer" : "Cover")")
    }

    /// A View-menu item: glyph + label, with a check on the active one.
    func viewModeLabel(_ title: String, icon: LucideIcon.Name, active: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(lucide: active ? .check : icon)
        }
    }

    /// The cover / video / visualizer slot: a pager of covers keyed by track
    /// (see FeedCoverPager) — in the normal layout it's just the playing
    /// track's page; in full-screen mode the drag brings in its neighbours.
    var artworkOrVisualizer: some View {
        FeedCoverPager(
            stage: stage,
            model: model,
            side: artworkSize,
            fullWidth: size.width,
            fullScreen: stageFullScreen,
            cornerRadius: expanded ? 10 : 7,
            albumOffset: stageFullScreen ? albumFullScreenOffset : 0,
            videoOffset: stageFullScreen ? videoFullScreenOffset : 0
        )
        // Normal layout: a track change crossfades. Full-screen: pages slide,
        // never fade (a fade ghosted the old cover over the new one).
        .animation(stageFullScreen ? nil : .smooth(duration: 0.3), value: stage.feedAnchor(current: model.state.currentMediaID))
        // Entrance: the cover settles in a beat after the card expands, with a
        // gentle scale. Once per expansion (reset on collapse).
        .scaleEffect(coverEntranceDone ? 1 : 0.92)
        .opacity(coverEntranceDone ? 1 : 0)
        .onAppear {
            guard !coverEntranceDone else { return }
            withAnimation(.smooth(duration: 0.4).delay(0.12)) { coverEntranceDone = true }
        }
    }

    @ViewBuilder
    func artwork(_ art: Artwork, cornerRadius: CGFloat? = nil) -> some View {
        ArtworkView(
            art,
            cornerRadius: cornerRadius ?? (expanded ? 10 : 7),
            background: Color(.palette.playerCard.artworkBackground),
            videoAspectFit: true,
            loadingPlaceholder: true,
            side: artworkSize
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
                // The comment playback is at, floating over the top of the
                // artwork — in full-screen mode too, at the same spot (it
                // doesn't ride down with the cover). Steps aside while the
                // feed pages to another track.
                .overlay(alignment: .topTrailing) {
                    LiveCommentToast(model: commentsModel) {
                        withAnimation(.smooth(duration: 0.32)) { selectedPanel = 1 }
                    }
                    .padding(.horizontal, Const.horizontalPadding + 12)
                    .padding(.top, 12)
                    // Same spot in both modes — it doesn't follow the cover down.
                    .modifier(FeedPagingFade(stage: stage))
                }
                .overlay(alignment: .bottomTrailing) {
                    if canShowVisualizer {
                        visualizerToggleButton
                            // Inside the centered square's bottom-right corner
                            // (the square is inset `horizontalPadding` per side).
                            .padding(.trailing, Const.horizontalPadding + 10)
                            .padding(.bottom, 10)
                            // Hides with the rest of the controls in immersive
                            // mode (tap anywhere restores them).
                            .opacity(stageFullScreen ? 0 : 1)
                            .allowsHitTesting(!stageFullScreen)
                    }
                }
                .padding(.bottom, artworkVerticalPadding)

            NowPlayingInfoStrip()
                // Align the About + buttons with the title, scrubber and the
                // rest of the player content (same inset everywhere).
                .padding(.horizontal, ViewConst.playerCardPaddings)
                // Steps aside while the feed pages: it describes the playing
                // track, so it returns once the swipe has landed.
                .modifier(FeedPagingFade(stage: stage))
                // Stays in full-screen mode, riding down with the cover to sit
                // just above the minimized controls.
                .offset(y: stageFullScreen ? fullScreenStripOffset : 0)
                // Hidden for workspace files — which have no description,
                // playlist or save actions. Faded, never unmounted: keeping it
                // in the layout is what makes a file and a track occupy exactly
                // the same space.
                .opacity(isWorkspaceFile ? 0 : 1)
                // Invisible must also mean untappable — otherwise the About sheet
                // opens from blank space.
                .allowsHitTesting(!isWorkspaceFile)
        }
        // A little below the safe-area edge so the cover doesn't hug the notch and
        // the stack reads more vertically centred (kept in sync with mainContentHeight).
        .padding(.top, artworkTopInset)
    }

}

// MARK: - Feed pager

/// The cover slot as a vertical pager. Each page is one TRACK's view (keyed by
/// its id), placed `slot` pages from the centre and shifted by the feed drag.
/// Landing a swipe re-centres on the page that slid in — the same view, at the
/// same spot — so a track change never rebuilds or reloads a cover. Only the
/// playing track's page can show its video / leave room for the visualizer;
/// any other page (or a video still loading) shows the cover.
private struct FeedCoverPager: View {
    let stage: PlayerStageModel
    let model: PlayerController
    let side: CGFloat
    let fullWidth: CGFloat
    let fullScreen: Bool
    let cornerRadius: CGFloat
    /// Full-screen drop for an album square / a full-width video box.
    let albumOffset: CGFloat
    let videoOffset: CGFloat

    private struct Page: Identifiable {
        let id: MediaID
        let slot: Int
    }

    var body: some View {
        let anchor = stage.feedAnchor(current: model.state.currentMediaID)
        let drag = stage.feedDragY
        let page = stage.pageHeight
        ZStack(alignment: .top) {
            ForEach(pages(anchor: anchor, drag: drag)) { p in
                pageView(p.id)
                    .offset(y: CGFloat(p.slot) * page + drag)
                    // Pages slide in full-screen mode — they never fade in or
                    // out (a neighbour appearing inside a swipe's animation
                    // otherwise faded in as a ghost).
                    .transition(fullScreen ? .identity : .opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: boxHeight(anchor), alignment: .top)
    }

    /// The centre page, plus its neighbours while the feed is moving.
    private func pages(anchor: MediaID?, drag: CGFloat) -> [Page] {
        guard let anchor else { return [] }
        var result = [Page(id: anchor, slot: 0)]
        guard drag != 0 || stage.feedCommitting else { return result }
        let next = model.neighborID(of: anchor, 1)
        let previous = model.neighborID(of: anchor, -1)
        if let next, let previous, next == previous, next != anchor {
            // Two-track queue: the one neighbour sits on the side being dragged to.
            result.append(Page(id: next, slot: drag < 0 ? 1 : -1))
            return result
        }
        if let next, next != anchor { result.append(Page(id: next, slot: 1)) }
        if let previous, previous != anchor, previous != next { result.append(Page(id: previous, slot: -1)) }
        return result
    }

    // MARK: Page content

    private enum Content: Hashable {
        case cover(loading: Bool)
        case video
        case fullBleed   // portrait video / visualizer, drawn behind the player
    }

    private func content(for id: MediaID) -> Content {
        let isCurrent = id == model.state.currentMediaID
            && model.nowPlayingMeta?.audioURL == model.meta(for: id)?.audioURL
        guard isCurrent else { return .cover(loading: false) }
        if case .videoPlayer = model.display.artwork, model.videoReady {
            return model.isPortraitVideo ? .fullBleed : .video
        }
        if !model.display.isVideoTrack, model.showVisualizer, model.visualizerAvailable { return .fullBleed }
        return .cover(loading: model.display.isVideoTrack)
    }

    private func boxHeight(_ anchor: MediaID?) -> CGFloat {
        guard let anchor, case .video = content(for: anchor) else { return side }
        return fullScreen ? fullWidth : side
    }

    /// The playing track's page crossfades cover → video once the clip is
    /// actually playing (one animation for both, so the cover never sits
    /// over a half-loaded video).
    private func pageView(_ id: MediaID) -> some View {
        let content = content(for: id)
        return ZStack(alignment: .top) {
            pageContent(id, content)
                .id(content)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.35), value: content)
    }

    @ViewBuilder
    private func pageContent(_ id: MediaID, _ content: Content) -> some View {
        switch content {
        case let .cover(loading):
            let meta = model.meta(for: id)
            artwork(.placeholder(meta?.artwork, name: meta?.title), corner: cornerRadius)
                .frame(width: side, height: side)
                .overlay { if loading { ProgressView().tint(.white) } }
                .frame(maxWidth: .infinity)
                .offset(y: albumOffset)
        case .video:
            artwork(model.display.artwork, corner: fullScreen ? 0 : cornerRadius)
                .frame(maxWidth: .infinity)
                .frame(height: fullScreen ? fullWidth : side)
                .offset(y: videoOffset)
        case .fullBleed:
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: side)
        }
    }

    private func artwork(_ art: Artwork, corner: CGFloat) -> some View {
        ArtworkView(
            art,
            cornerRadius: corner,
            background: Color(.palette.playerCard.artworkBackground),
            videoAspectFit: true,
            loadingPlaceholder: true,
            side: side
        )
        .shadow(color: Color(.sRGBLinear, white: 0, opacity: 0.33), radius: 8, y: 10)
    }
}

/// Fades its content out while the feed pages (drag, slide, or landed ahead
/// of playback), back in once playback has caught up. Reads the per-frame
/// drag here so only this host re-renders.
private struct FeedPagingFade: ViewModifier {
    let stage: PlayerStageModel

    func body(content: Content) -> some View {
        FeedPagingFadeHost(stage: stage, content: content)
    }
}

private struct FeedPagingFadeHost<Content: View>: View {
    let stage: PlayerStageModel
    let content: Content

    var body: some View {
        let paging = stage.feedDragY != 0 || stage.feedCommitting || stage.anchorOverride != nil
        content
            .opacity(paging ? 0 : 1)
            .animation(.easeOut(duration: 0.18), value: paging)
    }
}

extension RegularNowPlaying {
    /// The expanded cover's side (the player spans the screen width) — what
    /// the feed's preloading sizes its cached covers to.
    static var coverSide: CGFloat {
        UIScreen.size.width - Const.horizontalPadding * 2
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    RegularNowPlaying(
        expanded: true,
        size: UIScreen.size,
        composerNamespace: Namespace().wrappedValue,
        selectedPanel: .constant(0),
        commentsAtTop: .constant(true),
        drag: PlayerDragState(),
        stage: PlayerStageModel()
    )
    .onAppear {
        playerController.mediaState = dependencies.mediaState
        playerController.player = dependencies.mediaPlayer
    }
    .background {
        ColorfulBackground(
            colors: playerController.colors
        )
        .overlay(Color(UIColor(white: 0.4, alpha: 0.5)))
    }
    .ignoresSafeArea()
    .environment(playerController)
}
