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
    /// When false (workspace file with no cover, or the comments panel is up) the
    /// cover doesn't glide into the expanded player — it just fades with the mini bar.
    var coverMatchEnabled: Bool = true
    var animationNamespace: Namespace.ID
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
    @ViewBuilder
    func artwork(cornerRadius: CGFloat) -> some View {
        if coverMatchEnabled {
            // Hidden once expanded so the matched-geometry source lives in the
            // expanded player — the cover glides between the two on expand/collapse.
            if !expanded {
                ArtworkView(
                    model.display.artwork,
                    cornerRadius: cornerRadius,
                    background: Color(.systemGray4)
                )
                .matchedGeometryEffect(
                    id: PlayerMatchedGeometry.artwork,
                    in: animationNamespace
                )
            }
        } else {
            // No expanded cover to glide to (file / comments panel) — keep it
            // rendered and let it fade with the mini bar's opacity.
            ArtworkView(
                model.display.artwork,
                cornerRadius: cornerRadius,
                background: Color(.systemGray4)
            )
        }
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
                        .foregroundStyle(model.isLoadingTrack ? Color.white.opacity(0.3) : .white)
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

    CompactNowPlaying(
        expanded: .constant(false),
        animationNamespace: Namespace().wrappedValue
    )
    .background(.gray)
    .environment(playerController)
    .onAppear {
        playerController.mediaState = dependencies.mediaState
        playerController.player = dependencies.mediaPlayer
    }
}
