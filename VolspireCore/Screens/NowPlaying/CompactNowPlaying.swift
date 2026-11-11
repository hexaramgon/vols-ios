//
//  CompactNowPlaying.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import SwiftUI

struct CompactNowPlaying: View {
    @Environment(PlayerController.self) var model
    @Binding var expanded: Bool
    @State var forwardAnimationTrigger: PlayerButtonTrigger = .one(bouncing: false)
    @State var viewWidth: CGFloat = .zero

    var body: some View {
        nowPlaying
            .frame(height: ViewConst.compactNowPlayingHeight)
            .contentShape(.rect)
            .transformEffect(.identity)
            .onTapGesture {
                withAnimation(.playerExpandAnimation) {
                    expanded = true
                }
            }
            .onGeometryChange(
                for: CGFloat.self,
                of: { $0.size.width },
                action: { viewWidth = $0 }
            )
    }
}

private extension CompactNowPlaying {
    /// The cover fades with the mini bar on expand / collapse.
    func artwork(cornerRadius: CGFloat) -> some View {
        ArtworkView(
            model.display.artwork,
            cornerRadius: cornerRadius,
            background: Color(.systemGray4)
        )
    }

    var inlinedBottomAccessory: Bool {
        let padding = UIScreen.size.width - viewWidth
        return padding > 60
    }

    var nowPlaying: some View {
        HStack(spacing: 0) {
            artwork(cornerRadius: 5)
                .frame(width: 42, height: 42)
            VStack(spacing: 0) {
                let title = model.display.title
                // TODO: MarqueeText
//                    let fade = ViewConst.playerCardPaddings
//                    let cfg = MarqueeText.Config(leftFade: fade, rightFade: fade)
//                    let title = "#STUPiDFACEDD"
//                    MarqueeText(title, config: cfg)
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.appFootnoteSemibold)
                    .id(model.display)
                let subtitle = model.display.subtitle
                Text(subtitle)
                    .font(.appCaption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(model.display)
            }
            .padding(.leading, 8)
            .geometryGroup()
            .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                PlayerButton(
                    label: {
                        Group {
                            switch model.playPauseButton {
                            case .pause: Image(systemName: "pause.fill")
                            default: Image(systemName: "play.fill")
                            }
                        }
                        .font(.system(size: 21, weight: .medium))
                        // Dimmed + non-interactive while the track loads.
                        .foregroundStyle(model.isLoadingTrack ? Color.vText4 : Color.vText)
                    },
                    onEnded: {
                        guard !model.isLoadingTrack else { return }
                        model.onPlayPause()
                    }
                )
                .allowsHitTesting(!model.isLoadingTrack)
                if !inlinedBottomAccessory {
                    PlayerButton(
                        label: {
                            PlayerButtonLabel(
                                type: model.forwardButton,
                                size: 26,
                                animationTrigger: forwardAnimationTrigger
                            )
                        },
                        onEnded: {
                            model.onForward()
                            DispatchQueue.main.async {
                                forwardAnimationTrigger.toggle(bouncing: true)
                            }
                        }
                    )
                    .disabled(!model.commandProfile.isSwitchTrackEnabled)
                }
            }
            // Centre play/pause's tap area on its icon: iOS stretches it into
            // the empty space on its left, but forward's frame cuts it off
            // right at the icon's edge — measured, it reached ~37pt left of
            // the icon's centre but only ~22pt right. This strip hands the
            // first 10pt of forward's frame (empty — forward's glyph starts
            // ~8pt in) to play/pause.
            .overlay(alignment: .leading) {
                if !inlinedBottomAccessory {
                    Color.clear
                        .frame(width: 10)
                        .contentShape(.rect)
                        .onTapGesture {
                            guard !model.isLoadingTrack else { return }
                            model.onPlayPause()
                        }
                        .offset(x: 44) // the play/pause button's width (miniPlayer config)
                }
            }
            .playerButtonStyle(.miniPlayer)
        }
        .padding(.leading, 16)
        .padding(.trailing, 13)
    }
}

extension PlayerButtonConfig {
    static var miniPlayer: Self {
        Self(
            size: 44,
            tint: .init(Palette.PlayerCard.translucent.withAlphaComponent(0.3)),
            showsPressFeedback: false
        )
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    CompactNowPlaying(expanded: .constant(false))
    .background(.gray)
    .environment(playerController)
    .onAppear {
        playerController.mediaState = dependencies.mediaState
        playerController.player = dependencies.mediaPlayer
    }
}
