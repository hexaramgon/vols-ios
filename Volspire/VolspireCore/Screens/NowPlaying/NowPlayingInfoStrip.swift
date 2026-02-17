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
        HStack(spacing: 12) {
            albumThumb
            slideshowPanels
            fxButton
        }
        .frame(height: 72)
        .onAppear { startAutoSlide() }
        .onDisappear { stopAutoSlide() }
        .sheet(isPresented: Bindable(controller).showingEffectsSheet) {
            AudioEffectsSheet()
                .environment(controller)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        default:
            ArtworkView(art, cornerRadius: 8)
                .frame(width: 72, height: 72)
        }
    }

    var fxButton: some View {
        let isActive = controller.audioEffects != .default
        return Button {
            controller.showingEffectsSheet = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                Text("FX")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.7))
            .frame(width: 44, height: 72)
        }
    }
}

// MARK: - Slideshow

private extension NowPlayingInfoStrip {
    var slideshowPanels: some View {
        TabView(selection: $currentPage) {
            trackInfoPanel.tag(0)
            artistPanel.tag(1)
            statsPanel.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            pageIndicator
                .padding(.bottom, 2)
        }
    }

    // Panel 1: Title & Subtitle
    var trackInfoPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(controller.display.title.isEmpty ? "—" : controller.display.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
            Text(controller.display.subtitle.isEmpty ? "Unknown" : controller.display.subtitle)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }

    // Panel 2: Artist & Genre
    var artistPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(controller.nowPlayingMeta?.artist ?? "Unknown Artist")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "person.fill")
                    .font(.caption)
            }
            Label {
                Text(controller.nowPlayingMeta?.genre ?? "Music")
                    .font(.caption)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "guitars.fill")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }

    // Panel 3: Playback Stats
    var statsPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress = controller.progress {
                Label {
                    Text("Duration: \(progress.duration.asTimeString(style: .positional))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption)
                }
                Label {
                    let pct = progress.duration > 0
                        ? Int((progress.elapsedTime / progress.duration) * 100)
                        : 0
                    Text("\(pct)% played")
                        .font(.caption)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                }
            } else {
                Text("No playback data")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
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
