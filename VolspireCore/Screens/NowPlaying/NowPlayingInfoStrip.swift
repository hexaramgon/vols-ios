//
//  NowPlayingInfoStrip.swift
//  Volspire
//

import DesignSystem
import Kingfisher
import Player
import Services
import SwiftUI

/// A row below the Now Playing artwork: small album cover on the left,
/// auto-sliding info panels on the right.
struct NowPlayingInfoStrip: View {
    @Environment(PlayerController.self) var controller
    @State private var currentPage: Int = 0
    @State private var timer: Timer?
    @State private var showFolderPicker = false
    @State private var showAddToPlaylist = false

    /// Thumbnail size derived from screen width (roughly 30% of width).
    private var thumbSize: CGFloat {
        round(UIScreen.size.width * 0.3)
    }

    private var currentTrackId: String? {
        controller.state.currentMediaID?.value
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            slideshowPanels          // About / Credits (left, card background)
            actionsColumn            // Actions (right, no background)
        }
        .frame(height: thumbSize)
        // Resolve the strip's geometry as one unit so it tracks the drag-to-dismiss
        // rigidly with the rest of the player (otherwise it "moves first").
        .geometryGroup()
        .onAppear { startAutoSlide() }
        .onDisappear { stopAutoSlide() }
        .sheet(isPresented: $showFolderPicker) {
            if let id = currentTrackId {
                WorkspaceFolderPicker(trackId: id)
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let id = currentTrackId {
                AddToPlaylistSheet(trackId: id)
            }
        }
    }
}

// MARK: - Actions (permanent, right side, no background)

private extension NowPlayingInfoStrip {
    /// Two compact circular icon actions on the right: Add to playlist on top,
    /// Workspace (add to workspace) below — saves the horizontal space the labels took.
    var actionsColumn: some View {
        VStack(spacing: 12) {
            circleAction(.listMusic, label: "Add to playlist") { showAddToPlaylist = true }
            circleAction(.folder, label: "Workspace") { showFolderPicker = true }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Slideshow

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

    var slideshowPanels: some View {
        // Pure-SwiftUI crossfade slideshow (no UIPageViewController) so the card
        // tracks the drag-to-dismiss in lockstep with the rest of the player.
        ZStack(alignment: .bottomLeading) {
            descriptionPanel.opacity(currentPage == 0 ? 1 : 0)
            creditsPanel.opacity(currentPage == 1 ? 1 : 0)
        }
        // Bottom-align the content so it sits low, right above the title (rather
        // than floating in the middle of the strip with a big gap below it).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.vertical, 12)
        .environment(\.colorScheme, .dark)
        // Keep panel content within bounds — never let it spill onto the artwork /
        // like row above or the track title below.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // Panel 1: About (description + tags)
    var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader("About")

            if let desc = controller.trackDetail?.description, !desc.isEmpty {
                Text(desc)
                    .font(.appFootnote)
                    .lineLimit(1)
                    .foregroundStyle(Theme.body)
                    .infoTextShadow()
            } else {
                Text("No description provided.")
                    .font(.appFootnote)
                    .italic()
                    .foregroundStyle(Theme.muted)
                    .infoTextShadow()
            }

            // Tags carry their own white background, so they need no shadow.
            if let tags = controller.trackDetail?.metadata?.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tagChip($0) }
                }
            }
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Panel 2: Credits — the people on the track, capped to one compact line.
    var creditsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader("Credits")

            HStack(spacing: 8) {
                creditAvatar
                Text(creditsSummary)
                    .font(.appFootnote)
                    .lineLimit(1)
                    .foregroundStyle(Theme.body)
                    .infoTextShadow()
            }
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The primary (artist) avatar shown beside the credits line.
    var creditAvatar: some View {
        let username = controller.trackDetail?.artist?.username ?? controller.nowPlayingMeta?.artist
        let url = controller.trackDetail?.artist?.profileImageUrl.flatMap { URL(string: $0) }
        return Group {
            if let url {
                KFImage(url).downsampled(to: 26).resizable().scaledToFill()
            } else {
                Text(String(username?.first ?? "?").uppercased())
                    .font(.appCaption2Bold)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
        .background(Color(white: 0.15))
        .clipShape(Circle())
    }

    /// Artist + collaborators as a single "·"-joined line.
    var creditsSummary: String {
        var people: [String] = []
        if let artist = controller.trackDetail?.artist?.username ?? controller.nowPlayingMeta?.artist {
            people.append("@\(artist)")
        }
        if let credits = controller.trackDetail?.credits {
            people.append(contentsOf: credits.compactMap { $0.username.map { "@\($0)" } })
        }
        return people.isEmpty ? "No credits listed." : people.joined(separator: "  ·  ")
    }

    func tagChip(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.appCaption2Medium)
            .foregroundStyle(Color(white: 0.1))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.white, in: Capsule())
    }

    /// A circular icon action — a see-through blurred fill so the background
    /// behind it (incl. a bright full-bleed video) shows through, blurred.
    func circleAction(_ icon: LucideIcon.Name, label: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            LucideIcon(icon, .lg)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    func panelHeader(_ text: String) -> some View {
        Text(text)
            .font(.appMicroSemibold)
            .tracking(0.6)
            .foregroundStyle(Theme.header)
            .textCase(.uppercase)
            .infoTextShadow()
    }

}

private extension View {
    /// Soft dark drop shadow so white text stays legible over a bright video.
    /// Applied per-text (not the whole panel) so the white-backed tag chips are
    /// left untouched.
    func infoTextShadow() -> some View {
        shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

// MARK: - Auto-Slide Timer

private extension NowPlayingInfoStrip {
    func startAutoSlide() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentPage = (currentPage + 1) % 2
                }
            }
        }
    }

    func stopAutoSlide() {
        timer?.invalidate()
        timer = nil
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

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalSize: CGSize = .zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalSize.width = max(totalSize.width, x - spacing)
            totalSize.height = max(totalSize.height, y + rowHeight)
        }
        return (origins, totalSize)
    }
}
