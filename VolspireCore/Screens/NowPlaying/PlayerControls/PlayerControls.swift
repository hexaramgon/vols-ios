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
    /// True for a full-bleed portrait video: drops the transport down to sit just
    /// above the bottom bar (TikTok-style). Off (default) keeps it floating up
    /// under the artwork for audio / landscape video. Animated when it changes.
    var fullBleed: Bool = false
    /// Minimized (immersive video) — drops the title, and the bottom action row,
    /// leaving just a compact transport (scrubber + playback buttons) at the bottom.
    var minimized: Bool = false

    /// Displayed comment count. Holds the last known value through a track switch
    /// (when `trackDetail` briefly goes nil) so the pill doesn't blank out and
    /// resize — it just rolls to the new count.
    /// Measured transport height, so the "raised" (non-full-bleed) inset can be
    /// computed as "fill the rest of the space above the bottom bar".
    @State private var transportHeight: CGFloat = 190
    /// Debounces the height measurement — see `transportStack`.
    @State private var measureWork: DispatchWorkItem?

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
                        guard h > 0, abs(h - transportHeight) > 1 else { return }
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
            .animation(.smooth(duration: 0.4), value: fullBleed)
            .animation(.easeInOut(duration: 0.3), value: minimized)
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

            TimingIndicator(spacing: spacing)
                .padding(.top, spacing)
                .padding(.horizontal, ViewConst.playerCardPaddings)
                .padding(.horizontal, -ElasticSliderConfig.playbackProgress.growth)

            // Smaller transport buttons when minimized.
            PlayerButtons(compact: minimized)
                .padding(.horizontal, ViewConst.playerCardPaddings)
        }
    }
}

private extension CGSize {
    var verticalSpacing: CGFloat { height * 0.04 }
}

private extension PlayerControls {
    /// How far the transport sits from the bottom.
    /// - Low (full-bleed video, or comments open): reserve just the bottom-bar
    ///   footprint so it sits right above it.
    /// - High (default): fill the space below so it pins up under the artwork.
    func transportInset(controlsHeight: CGFloat) -> CGFloat {
        // Minimized: no bottom bar, so the compact transport sits a touch above the
        // home indicator (tighter than the full layout).
        if minimized { return max(ViewConst.safeAreaInsets.bottom, 12) + 2 }
        if fullBleed || commentsOpen { return bottomBarFootprint }
        return max(bottomBarFootprint, controlsHeight - transportHeight)
    }

    /// Collapsed comment-composer footprint (top pad + avatar pill + bottom inset).
    var bottomBarFootprint: CGFloat {
        64 + max(ViewConst.safeAreaInsets.bottom, 14)
    }
}

private extension PlayerControls {
    var palette: Palette.PlayerCard.Type {
        UIColor.palette.playerCard.self
    }

    /// The bottom row morphs between the action row (AirPlay · Comments · Share)
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
    /// "Comments" (center) · Share (right).
    var bottomActionsRow: some View {
        HStack(spacing: 0) {
            AirPlayButton(size: 24)
                .foregroundStyle(Color(palette.translucent))

            Spacer(minLength: 0)

            commentsButton

            Spacer(minLength: 0)

            Button {
                shareTrack()
            } label: {
                LucideIcon(.share2, .xl)
                    .foregroundStyle(Color(palette.translucent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ViewConst.playerCardPaddings)
    }

    /// Shares the track using the same single-message format as the Library share,
    /// with the track's web link (`/track/{id}`) appended.
    func shareTrack() {
        var shareText = "Check out \"\(model.display.title)\" on Volspire!"
        if let trackId = model.state.currentMediaID?.value {
            shareText += " https://volspire.com/track/\(trackId)"
        }
        AnalyticsService.shared?.log(.shareClicked, trackId: model.state.currentMediaID?.value, metadata: ["kind": "track", "method": "share_sheet"])

        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            activityVC.popoverPresentationController?.sourceView = presenter.view
            presenter.present(activityVC, animated: true)
        }
    }

    /// A text "Comments" pill button that opens the comments panel.
    /// (Count removed for now — see todolist "Comments-button count".)
    var commentsButton: some View {
        Button { onComment() } label: {
            Text("Comments")
                .font(.appCallout)
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
                    MarqueeText(title, config: cfg)
                        .transformEffect(.identity)
                        .font(.appTitle2)
                        .foregroundStyle(Color(palette.opaque))
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    MarqueeText(subtitle, config: cfg)
                        .transformEffect(.identity)
                        .font(.appBodyLarge)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                        .contentShape(.rect)
                        .onTapGesture {
                            if let userId = model.trackDetail?.artist?.userId {
                                model.pendingProfileNavigation = userId
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Cross-fade title + artist together with the cover on track change.
                .id(model.display)
                .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: model.display)
            .padding(.leading, ViewConst.playerCardPaddings)

            // Workspace files aren't real, shareable tracks — drop the save /
            // playback-fx actions; only comments apply.
            if model.currentFileId == nil {
                HStack(spacing: 18) {
                    saveButton
                    fxButton
                }
                .padding(.trailing, ViewConst.playerCardPaddings)
            }
        }
    }

    /// Save (bookmark) button — to the left of the effects button.
    var saveButton: some View {
        Button {
            Task { await model.toggleSave() }
        } label: {
            LucideIcon(model.isSaved ? .bookmarkFill : .bookmark, .xl)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
        }
    }

    /// Audio-effects button — same `SlidersHorizontal` icon the web app uses.
    var fxButton: some View {
        let isActive = model.audioEffects != .default
        return Button {
            model.showingEffectsSheet = true
        } label: {
            LucideIcon(.slidersHorizontal, .xl)
                .foregroundStyle(isActive ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(Color.white))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
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
}
