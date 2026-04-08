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

    /// Delays content appearance so the background animation can catch up.
    @State private var showContent: Bool = false
    @State private var selectedPanel: Int = 0

    var body: some View {
        VStack() {
            if expanded {
                TabView(selection: $selectedPanel) {
                    // Panel 1: Artwork / Visualizer + Info Strip
                    VStack() {
                        artworkOrVisualizer
                            .matchedGeometryEffect(
                                id: PlayerMatchedGeometry.artwork,
                                in: animationNamespace
                            )
                            .frame(height: artworkSize)
                            .overlay(alignment: .bottom) {
                                actionIconsRow
                                    .offset(y: 42)
                            }
                            .padding(.bottom, artworkVerticalPadding)
                            .padding(.horizontal, 25)

                        NowPlayingInfoStrip()
                            .padding(.horizontal, 25)
                    }
                    .tag(0)

                    // Panel 2: Comments
                    NowPlayingCommentsPanel()
                        .padding(.vertical, 16)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .opacity(showContent ? 1 : 0)

                PlayerControls()
                    .frame(height: size.height * 0.32)
                    .opacity(showContent ? 1 : 0)

                // Spacer()
                //     .frame(height: size.height * 0.05)
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                // Delay content reveal until the background has animated in
                withAnimation(.easeIn(duration: 0.25).delay(Animation.playerExpandAnimationDuration * 0.6)) {
                    showContent = true
                }
            } else {
                // Hide immediately when collapsing
                showContent = false
            }
        }
    }
}

private extension RegularNowPlaying {
    enum Const {
        static let horizontalPadding: CGFloat = 25
    }

    /// Artwork square dimension (same as before).
    var artworkSize: CGFloat {
        size.width - Const.horizontalPadding * 2
    }

    /// Top + bottom padding around the artwork.
    var artworkVerticalPadding: CGFloat {
        size.height < 700 ? 15 : 40
    }


    var grip: some View {
        Capsule()
            .fill(.white.secondary)
            .frame(width: 40, height: 5)
    }

    var isVideo: Bool {
        if case .videoPlayer = model.display.artwork { return true }
        return false
    }

    @ViewBuilder
    var artworkOrVisualizer: some View {
        let artworkSize = size.width - Const.horizontalPadding * 2
        Group {
            if isVideo {
                artwork(model.display.artwork)
            } else if model.showAlbumArt {
                artwork(model.display.albumArtwork)
            } else {
                NowPlayingVisualizer(
                    spectrum: model.visualizerSpectrum,
                    albumArtwork: nil,
                    isPlaying: model.state.isPlaying,
                    backgroundColor: model.colors.first.map { Color($0) } ?? .black,
                    rawSamples: model.rawAudioSamples
                )
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipped()
    }

    @ViewBuilder
    func artwork(_ art: Artwork) -> some View {
        let small = !model.state.isPlaying
        ArtworkView(
            art,
            cornerRadius: expanded ? 10 : 7,
            background: Color(.palette.playerCard.artworkBackground)
        )
        .shadow(
            color: Color(.sRGBLinear, white: 0, opacity: small ? 0.13 : 0.33),
            radius: small ? 3 : 8,
            y: small ? 3 : 10
        )
    }

    var actionIconsRow: some View {
        HStack {
            HStack(spacing: 16) {
                Button { } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                            .font(.title2)
                        Text(formatCount(model.trackDetail?.saves ?? 0))
                            .font(.callout)
                    }
                }
                Button { } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.title2)
                        Text(formatCount(model.trackDetail?.likes ?? 0))
                            .font(.callout)
                    }
                }
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedPanel = selectedPanel == 1 ? 0 : 1
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedPanel == 1 ? "bubble.right.fill" : "bubble.right")
                        .font(.title2)
                    Text(formatCount(model.trackDetail?.comments ?? 0))
                        .font(.callout)
                }
            }
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    private func formatCount(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return String(format: "%.1fK", Double(count) / 1_000)
        default: return String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    RegularNowPlaying(
        expanded: true,
        size: UIScreen.size,
        animationNamespace: Namespace().wrappedValue
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
