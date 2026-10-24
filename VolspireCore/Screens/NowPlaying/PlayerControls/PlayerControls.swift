//
//  PlayerControls.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import MediaLibrary
import Services
import SwiftUI

struct PlayerControls: View {
    @Environment(PlayerController.self) var model
    /// Opens (toggles) the comments panel — wired from the now-playing pager.
    var onComment: () -> Void = {}
    /// Shared comments state — the action row morphs into this comment input bar.
    var commentsModel = NowPlayingCommentsModel()
    /// Namespace for the Comments-button → input-bar morph.
    var composerNamespace: Namespace.ID?
    /// True while comments are open — swaps the action row for the input bar.
    var commentsOpen: Bool = false
    /// Full-screen mode — drops the transport buttons and the bottom action row,
    /// leaving the title + scrubber at the bottom.
    var minimized: Bool = false
    /// Reports how far the title drops when minimized (see `titleDrop`).
    var onTitleDrop: (CGFloat) -> Void = { _ in }

    /// Measured transport height, so the "raised" (non-full-bleed) inset can be
    /// computed as "fill the rest of the space above the bottom bar".
    @State private var transportHeight: CGFloat = 190
    /// Debounces the height measurement — see `transportStack`.
    @State private var measureWork: DispatchWorkItem?
    /// Track "…" options sheet (see PlayerTrackOptions.swift).
    @State private var showTrackOptions = false
    /// Measured transport-buttons height (they leave the stack when minimized).
    @State private var buttonsHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let spacing = geo.size.verticalSpacing / 8
            // One structure for both states — only the bottom inset differs, so the
            // transport slides between the two positions instead of snapping.
            VStack(spacing: spacing) {
                Spacer(minLength: 0)
                transportStack(spacing: spacing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        // Record the height only once layout goes quiet. During the
                        // minimize/restore animation the transport resizes every
                        // frame, and writing the height back mid-flight retargets
                        // the position animation each frame — visible hitching.
                        measureWork?.cancel()
                        // Only the FULL transport's height feeds the raised
                        // inset — the compact (minimized) one is shorter, and
                        // recording it made the restore aim too high, then
                        // re-measure and jump. Minimized uses a fixed inset.
                        guard !minimized, h > 0, abs(h - transportHeight) > 1 else { return }
                        let work = DispatchWorkItem { transportHeight = h }
                        measureWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
                    }
            }
            .padding(.bottom, transportInset(controlsHeight: geo.size.height))
            // The bottom bar (action row / comment input) floats at the very bottom —
            // hidden when minimized. Faded rather than unmounted: the AirPlay
            // button wraps a UIKit AVRoutePickerView, and re-creating it on every
            // reveal hitches the first frame of the animation.
            .overlay(alignment: .bottom) {
                bottomBar
                    .padding(.bottom, commentsOpen ? 0 : max(ViewConst.safeAreaInsets.bottom, 12) + 10)
                    .opacity(minimized ? 0 : 1)
                    .allowsHitTesting(!minimized)
            }
            .animation(.easeInOut(duration: 0.3), value: minimized)
            .onChange(of: titleDrop(controlsHeight: geo.size.height, spacing: spacing), initial: true) { _, drop in
                guard !minimized, !commentsOpen, buttonsHeight > 0 else { return }
                onTitleDrop(drop)
            }
        }
        .sheet(isPresented: Bindable(model).showingEffectsSheet) {
            AudioEffectsSheet()
                .environment(model)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
        }
    }

    private func transportStack(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            trackInfo

            TimingIndicator(spacing: spacing, minimized: minimized)
                // Timed comments: a dot on the track at each one.
                .overlay(alignment: .topLeading) {
                    TimedCommentsOverlay(model: commentsModel)
                }
                .padding(.top, spacing)
                .padding(.horizontal, ViewConst.playerCardPaddings)
                .padding(.horizontal, -ElasticSliderConfig.playbackProgress.growth)

            // Minimized (full-screen video): the transport buttons go — tracks
            // change by swiping, tap restores the controls. They fade while the
            // title + scrubber glide down into the space they leave.
            if !minimized {
                PlayerButtons()
                    .padding(.horizontal, ViewConst.playerCardPaddings)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonsHeight = $0 }
                    .transition(.opacity)
            }
        }
    }
}

private extension CGSize {
    var verticalSpacing: CGFloat { height * 0.04 }
}

private extension PlayerControls {
    /// How far the transport sits from the bottom.
    /// - Low (comments open): reserve just the bottom-bar
    ///   footprint so it sits right above it.
    /// - High (default): fill the space below so it pins up under the artwork.
    func transportInset(controlsHeight: CGFloat) -> CGFloat {
        // Minimized: no bottom bar, so the compact transport sits a touch above the
        // home indicator (tighter than the full layout).
        if minimized { return max(ViewConst.safeAreaInsets.bottom, 12) + 2 }
        if commentsOpen { return bottomBarFootprint }
        return max(bottomBarFootprint, controlsHeight - transportHeight)
    }

    /// How far the title moves down between the full and minimized layouts:
    /// the change in bottom inset plus the buttons (and their gap) leaving.
    func titleDrop(controlsHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        let fullInset = max(bottomBarFootprint, controlsHeight - transportHeight)
        let minimizedInset = max(ViewConst.safeAreaInsets.bottom, 12) + 2
        return fullInset - minimizedInset + buttonsHeight + spacing
    }

    /// Collapsed comment-composer footprint (top pad + avatar pill + bottom inset).
    var bottomBarFootprint: CGFloat {
        64 + max(ViewConst.safeAreaInsets.bottom, 14)
    }
}

private extension PlayerControls {
    /// Minimized is the immersive state: the blurred backdrop is gone and the
    /// transport sits on bare video, so it needs the heavy shadow. The default
    /// player keeps its blur, and there the gentle long-standing one is enough.
    var overlayShadow: PlayerOverlayShadow { minimized ? .strong : .subtle }

    var palette: Palette.PlayerCard.Type {
        UIColor.palette.playerCard.self
    }

    /// The bottom row morphs between the action row (AirPlay · Comments · "…")
    /// and the comment input bar when comments open.
    @ViewBuilder
    var bottomBar: some View {
        if commentsOpen {
            CommentComposerBar(model: commentsModel, composerNamespace: composerNamespace)
                .transition(.opacity)
        } else {
            bottomActionsRow
                .transition(.opacity)
        }
    }

    /// Bottom row pinned under the transport controls: AirPlay (left) ·
    /// "Comments" (center) · track options "…" (right).
    var bottomActionsRow: some View {
        HStack(spacing: 0) {
            AirPlayButton(size: 24)
                .foregroundStyle(Color(palette.translucent))

            Spacer(minLength: 0)

            commentsButton

            Spacer(minLength: 0)

            Button {
                showTrackOptions = true
            } label: {
                // Same size token as the hero-overlay "…" buttons (profile /
                // detail pages), so all the floating ellipses match.
                LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                    .foregroundStyle(Color(palette.translucent))
            }
            .buttonStyle(.plain)
            // Workspace files aren't real tracks — no share/report/block options.
            // Kept in layout (invisible) so the Comments pill stays centered.
            .opacity(model.currentFileId == nil ? 1 : 0)
            .allowsHitTesting(model.currentFileId == nil)
        }
        .padding(.horizontal, ViewConst.playerCardPaddings)
    }

    /// A text "Comments" pill button that opens the comments panel.
    /// (Count removed for now — see todolist "Comments-button count".)
    var commentsButton: some View {
        Button { onComment() } label: {
            Text("Comments")
                .font(.appSubheadlineMedium)
                .foregroundStyle(Color(palette.opaque))
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        // Morphs into the comment input bar when comments open.
        .matchedComposer(composerNamespace)
    }

    @ViewBuilder
    var trackInfo: some View {
        HStack(alignment: .center) {
            ZStack {
                VStack(alignment: .leading, spacing: 4) {
                    let fade = ViewConst.playerCardPaddings
                    let cfg = MarqueeText.Config(leftFade: 0, rightFade: fade)
                    let title = model.display.title.isEmpty ? " " : model.display.title
                    let subtitle = model.display.subtitle.isEmpty ? " " : model.display.subtitle
                    // The app's title + byline: page-title type, then the
                    // artist as "@handle" in the secondary ink (as on every
                    // row and card, and the web player's hero).
                    MarqueeText(title, config: cfg)
                        .transformEffect(.identity)
                        .font(.appTitle2)
                        .foregroundStyle(Color.vText)
                        .playerOverlayShadow(overlayShadow)
                    MarqueeText(handle(subtitle), config: cfg)
                        .transformEffect(.identity)
                        .font(.appSubheadline)
                        // Same secondary ink in both modes (the overlay shadow
                        // keeps it readable over bare video).
                        .foregroundStyle(Color.vText2)
                        .playerOverlayShadow(overlayShadow)
                        .contentShape(.rect)
                        .onTapGesture {
                            // Resolves for workspace files too (their uploader),
                            // not just tracks with loaded detail.
                            if let userId = model.currentArtistUserId {
                                model.pendingProfileNavigation = userId
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Title + artist fade up (6pt) on track change, with the cover's
                // cross-fade — the web hero's 0.3s title entrance.
                .id(model.display)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: model.display)
            .padding(.leading, ViewConst.playerCardPaddings)

            // Workspace files aren't real, shareable tracks — no save / playback-fx
            // actions. Kept in layout (invisible), like the "…" above: removing
            // them re-flowed the title as a folder queue stepped from a track to a
            // file, which is exactly the movement this player is trying not to make.
            HStack(spacing: 18) {
                PlayerCreditsFacepile()
                fxButton
            }
            // The fx glyph is centred in a 32pt circle; pull the pair in so its
            // centre lands on the same column as the strip's Playlist /
            // Workspace icons and the repeat button (26pt glyphs on the inset).
            .padding(.trailing, ViewConst.playerCardPaddings - 3)
            .opacity(model.currentFileId == nil ? 1 : 0)
            .allowsHitTesting(model.currentFileId == nil)
        }
        .playerTrackOptions(isPresented: $showTrackOptions)
    }

    /// "@name" for a username (they never contain spaces); anything else
    /// (a stream label, the blank placeholder) as-is.
    func handle(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.hasPrefix("@") else { return name }
        return "@\(trimmed)"
    }

    /// Audio-effects button — same `SlidersHorizontal` icon the web app uses.
    var fxButton: some View {
        let isActive = model.audioEffects != .default
        return Button {
            model.showingEffectsSheet = true
        } label: {
            // Engaged (any non-default edit) = the web hero pills' selected
            // state: white with a black glyph, not an accent tint.
            LucideIcon(.slidersHorizontal, isActive ? .lg : .xl)
                .foregroundStyle(isActive ? Color.black : Color.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white).opacity(isActive ? 1 : 0))
                .playerOverlayShadow(isActive ? .off : overlayShadow)
                .animation(.easeInOut(duration: 0.18), value: isActive)
        }
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController()
    ZStack(alignment: .bottom) {
        PreviewBackground()
        PlayerControls()
            .frame(height: 300)
    }
    .environment(playerController)
    .environment(Dependencies.stub)
}
