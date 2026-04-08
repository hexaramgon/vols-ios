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

    /// Thumbnail size derived from screen width (roughly 30% of width).
    private var thumbSize: CGFloat {
        round(UIScreen.size.width * 0.3)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            albumThumb
            slideshowPanels
        }
        .frame(height: thumbSize)
        .onAppear { startAutoSlide() }
        .onDisappear { stopAutoSlide() }
    }
}

// MARK: - Album Thumbnail

private extension NowPlayingInfoStrip {
    @ViewBuilder
    var albumThumb: some View {
        Group {
            if controller.showAlbumArt {
                // Main area shows album art, so show mini visualizer here
                NowPlayingVisualizer(
                    spectrum: controller.visualizerSpectrum,
                    albumArtwork: nil,
                    isPlaying: controller.state.isPlaying,
                    backgroundColor: controller.colors.first.map { Color($0) } ?? .black,
                    rawSamples: controller.rawAudioSamples
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                // Main area shows visualizer, so show album art here
                ArtworkView(controller.display.albumArtwork, cornerRadius: 10)
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .onTapGesture {
            withAnimation(.smooth) {
                controller.showAlbumArt.toggle()
            }
        }
    }
}

// MARK: - Slideshow

private extension NowPlayingInfoStrip {
    var slideshowPanels: some View {
        TabView(selection: $currentPage) {
            descriptionPanel.tag(0)
            actionsPanel.tag(1)
            creditsPanel.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .bottom) {
            pageIndicator
                .padding(.bottom, 6)
        }
    }

    // Panel 1: Description
    var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            if let desc = controller.trackDetail?.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .lineLimit(4)
                    .foregroundStyle(.white.opacity(0.8))
            }

            if let streams = controller.trackDetail?.streams, streams > 0 {
                Label {
                    Text("\(streams) streams")
                        .font(.caption)
                } icon: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    // Panel 2: Actions
    var actionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            FlowLayout(spacing: 8) {
                actionButton(icon: "arrow.down.circle", label: "Save")
                actionButton(icon: "cart", label: "Buy")
                actionButton(icon: "square.and.arrow.up", label: "Share")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    // Panel 3: Credits & Details
    var creditsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credits")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            Label {
                Text(controller.trackDetail?.artist?.username ?? controller.nowPlayingMeta?.artist ?? "Unknown")
                    .font(.caption)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "music.mic")
                    .font(.caption)
            }

            if let credits = controller.trackDetail?.credits, !credits.isEmpty {
                ForEach(Array(credits.sorted(by: { $0.key < $1.key })), id: \.key) { role, name in
                    Label {
                        Text("\(role): \(name)")
                            .font(.caption)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "person")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    func actionButton(icon: String, label: String) -> some View {
        Button {
            // TODO: Implement action
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12), in: Capsule())
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    // Page dots
    var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - Auto-Slide Timer

private extension NowPlayingInfoStrip {
    func startAutoSlide() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentPage = (currentPage + 1) % 3
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
