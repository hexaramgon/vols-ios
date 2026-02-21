//
//  NowPlayingInfoStrip.swift
//  Volspire
//

import DesignSystem
import Kingfisher
import Player
import SwiftUI

/// A row below the Now Playing artwork: small album cover on the left,
/// auto-sliding info panels on the right.
struct NowPlayingInfoStrip: View {
    @Environment(PlayerController.self) var controller
    @State private var currentPage: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            albumThumb
            slideshowPanels
        }
        .frame(height: 130)
        .onAppear { startAutoSlide() }
        .onDisappear { stopAutoSlide() }
    }
}

// MARK: - Album Thumbnail

private extension NowPlayingInfoStrip {
    @ViewBuilder
    var albumThumb: some View {
        let art = controller.display.artwork
        switch art {
        case let .videoPlayer(player):
            // For video tracks, show a small video preview
            PlayerVideoView(player: player)
                .frame(width: 130, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        default:
            ArtworkView(art, cornerRadius: 10)
                .frame(width: 130, height: 130)
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
        .overlay(alignment: .bottom) {
            pageIndicator
                .padding(.bottom, 2)
        }
    }

    // Panel 1: Description
    var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let genre = controller.nowPlayingMeta?.genre {
                Text(genre)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
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

            HStack(spacing: 16) {
                actionButton(icon: "arrow.down.circle", label: "Save")
                actionButton(icon: "cart", label: "Buy")
                actionButton(icon: "square.and.arrow.up", label: "Share")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    // Panel 3: Credits & Details
    var creditsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Credits")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)

            Label {
                Text(controller.nowPlayingMeta?.artist ?? "Unknown")
                    .font(.caption)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "music.mic")
                    .font(.caption2)
            }

            if let progress = controller.progress, progress.duration > 0 {
                Label {
                    Text(progress.duration.asTimeString(style: .positional))
                        .font(.caption)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption2)
                }
            }

            if let genre = controller.nowPlayingMeta?.genre {
                Label {
                    Text(genre)
                        .font(.caption)
                } icon: {
                    Image(systemName: "guitars.fill")
                        .font(.caption2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
    }

    func actionButton(icon: String, label: String) -> some View {
        Button {
            // TODO: Implement action
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.8))
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
