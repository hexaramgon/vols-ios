//
//  NowPlayingInfoStrip.swift
//  Volspire
//

import DesignSystem
import Kingfisher
import Player
import Services
import SwiftUI

/// A row below the Now Playing artwork: the About panel (description) plus
/// the action column. The credit facepile lives beside the effects button.
struct NowPlayingInfoStrip: View {
    @Environment(PlayerController.self) var controller
    @State private var showAddToPlaylist = false
    /// Height of the last CONFIRMED description — the in-flight skeleton holds
    /// this exact height so nothing moves until the next response arrives;
    /// the layout then animates to the new track's real height.
    @State private var descHeight: CGFloat = 17

    /// Thumbnail size derived from screen width (roughly 30% of width).
    private var thumbSize: CGFloat {
        round(UIScreen.size.width * 0.3)
    }

    private var currentTrackId: String? {
        controller.state.currentMediaID?.value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            infoPanel                // About + credit facepile (left)
            actionsColumn            // Actions (right, no background)
        }
        .frame(height: thumbSize)
        // Resolve the strip's geometry as one unit so it tracks the drag-to-dismiss
        // rigidly with the rest of the player (otherwise it "moves first").
        .geometryGroup()
        .sheet(isPresented: $showAddToPlaylist) {
            if let id = currentTrackId {
                AddToPlaylistSheet(trackId: id, alwaysDark: true)
            }
        }
    }
}

// MARK: - Actions (permanent, right side, no background)

private extension NowPlayingInfoStrip {
    /// Two compact circular icon actions on the right: Add to playlist on top,
    /// Save (bookmark) below — saves the horizontal space the labels took.
    var actionsColumn: some View {
        VStack(spacing: 12) {
            // list-plus is wider than the bookmark / sliders (its + hangs off
            // the right), so it draws a size down to line up with them.
            iconAction(.listPlus, label: "Add to playlist", size: 24) { showAddToPlaylist = true }
            // The shared save glyph (fill + pop + ripple on save).
            Button { Task { await controller.toggleSave() } } label: {
                // White when saved too (for now), like the player's other icons.
                SaveBookmarkIcon(saved: controller.isSaved, size: 26,
                                 idleColor: Color(Palette.PlayerCard.opaque),
                                 savedColor: Color(Palette.PlayerCard.opaque))
                    .frame(width: 26, height: 26)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isSaved ? "Saved" : "Save")
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Info panel

private extension NowPlayingInfoStrip {
    /// White text throughout (legible over a full-bleed video), with a drop shadow
    /// applied at the panel level.
    enum Theme {
        static let header = Color.white.opacity(0.9)
        static let body = Color.white
        static let muted = Color.white.opacity(0.7)
        static let role = Color.white.opacity(0.85)
        static let chipFill = Color(white: 0.04)      // ~neutral-950
        static let hairline = Color.white.opacity(0.12)
        static let border = Color.white.opacity(0.1)  // ~neutral-800/60
    }

    /// True once the fetched detail actually belongs to the playing track —
    /// only then may the description (or its absence) render.
    /// Workspace files have no track detail and count as loaded (defensive
    /// empty states: never claim "nothing" mid-fetch).
    var detailLoaded: Bool {
        if controller.currentFileId != nil { return true }
        guard let loaded = controller.trackDetail?.trackId,
              let current = controller.state.currentMediaID?.value else { return false }
        return loaded.caseInsensitiveCompare(current) == .orderedSame
    }

    var infoPanel: some View {
        // One panel: About (description + tags) with the credit facepile on the
        // header line — tapping the avatars slides up the full credits sheet.
        descriptionPanel
            // Bottom-align the content so it sits low, right above the title (rather
            // than floating in the middle of the strip with a big gap below it).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.vertical, 12)
            .environment(\.colorScheme, .dark)
            // Keep panel content within bounds — never let it spill onto the artwork /
            // like row above or the track title below.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // The panel as a whole rides the strip's BOTTOM edge (see `infoPanel`): the
    // About block left, the credits affordance right, with the panel's width as
    // the horizontal space between them.
    //
    // The two are centred against EACH OTHER rather than sharing a bottom edge.
    // The facepile is 28pt tall (24pt avatars + 2pt), while a one-line
    // description is ~16pt — bottom-aligning left that single line sitting
    // visibly below the "Credits" label it should read alongside. At the two-line
    // cap the heights are near enough that centring looks the same as before.
    var descriptionPanel: some View {
        HStack(alignment: .center, spacing: 8) {
            // The whole About block opens the full About sheet — the strip
            // truncates (one description line, capped tag row + "…"), the
            // sheet shows everything.
            Button {
                controller.aboutModal = .init(
                    artwork: controller.display.albumArtwork,
                    title: controller.display.title,
                    description: controller.trackDetail?.description,
                    tags: controller.trackDetail?.metadata?.tags ?? [],
                    duration: controller.progress?.duration
                )
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    // Layout only ever changes on a CONFIRMED response: the
                    // skeleton holds the previous description's exact height,
                    // then the block animates to the new track's real height
                    // (down to one line, up to two — whatever it actually is).
                    if !detailLoaded {
                        // Detail still in flight — shimmer bones, never the
                        // "No description" claim.
                        aboutSkeleton
                            .frame(height: descHeight, alignment: .topLeading)
                            .transition(.opacity)
                    } else if let desc = controller.trackDetail?.description, !desc.isEmpty {
                        Text(desc)
                            .font(.appFootnote)
                            .lineLimit(2)
                            .foregroundStyle(Color.vText)
                            .playerOverlayShadow()
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { descHeight = $0 })
                            .transition(.opacity)
                    }
                    // No description: nothing at all (no placeholder line).

                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!detailLoaded)
            // The description gets the whole width up to the action column
            // (the credits facepile that used to sit here moved out).
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One soft fade as the NEW detail lands — but a track change drops
        // the old description instantly. Animating that removal too kept the
        // previous track's text fading out for 0.3s while the strip itself
        // faded back in after a swipe, so the old description showed first.
        .animation(detailLoaded ? .easeInOut(duration: 0.3) : nil, value: detailLoaded)
    }

    /// A single description-line bone (the strip shows text only).
    var aboutSkeleton: some View {
        Capsule().fill(Color.white.opacity(0.16)).frame(width: 170, height: 11)
            .shimmering()
    }

    /// A bare icon action, sized and tinted like the transport's shuffle /
    /// repeat glyphs. Its trailing edge sits on the player inset, so the
    /// column lines up with the repeat button below.
    func iconAction(_ icon: LucideIcon.Name, label: String, size: CGFloat = 26,
                    action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: size)
                .foregroundStyle(Color(Palette.PlayerCard.opaque))
                // Fixed 26pt slot so a smaller glyph stays centred on the column.
                .frame(width: 26, height: 26)
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

}

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    ZStack {
        Color.black.ignoresSafeArea()
        NowPlayingInfoStrip()
            .padding(.horizontal, 25)
    }
    .environment(playerController)
}
