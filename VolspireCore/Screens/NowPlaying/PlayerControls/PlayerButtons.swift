//
//  PlayerButtons.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct PlayerButtons: View {
    @Environment(PlayerController.self) var model
    let spacing: CGFloat
    let imageSize: CGFloat = 34
    @State var backwardAnimationTrigger: PlayerButtonTrigger = .one(bouncing: false)
    @State var forwardAnimationTrigger: PlayerButtonTrigger = .one(bouncing: false)

    @State private var isShuffled = false
    @State private var repeatMode = 0 // 0 = off, 1 = all, 2 = one

    var body: some View {
        HStack(spacing: spacing) {
            // Shuffle button
            Button {
                isShuffled.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isShuffled ? .green : Color(Palette.PlayerCard.translucent))
            }
            let isSwitchDisabled: Bool = !model.commandProfile.isSwitchTrackEnabled
            PlayerButton(
                label: {
                    PlayerButtonLabel(
                        type: model.backwardButton,
                        size: imageSize,
                        animationTrigger: backwardAnimationTrigger
                    )
                },
                onEnded: {
                    DispatchQueue.main.async {
                        backwardAnimationTrigger.toggle(bouncing: true)
                    }
                    model.onBackward()
                }
            )
            .disabled(isSwitchDisabled)
            .blendMode(isSwitchDisabled ? .overlay : .normal)

            PlayerButton(
                label: {
                    PlayerButtonLabel(type: model.playPauseButton, size: imageSize)
                },
                onEnded: {
                    model.onPlayPause()
                }
            )

            PlayerButton(
                label: {
                    PlayerButtonLabel(
                        type: model.forwardButton,
                        size: imageSize,
                        animationTrigger: forwardAnimationTrigger
                    )
                },
                onEnded: {
                    DispatchQueue.main.async {
                        forwardAnimationTrigger.toggle(bouncing: true)
                    }
                    model.onForward()
                }
            )
            .disabled(isSwitchDisabled)
            .blendMode(isSwitchDisabled ? .overlay : .normal)
            // Repeat button
            Button {
                repeatMode = (repeatMode + 1) % 3
            } label: {
                Image(systemName: repeatMode == 2 ? "repeat.1" : "repeat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(repeatMode > 0 ? .green : Color(Palette.PlayerCard.translucent))
            }
        }
        .playerButtonStyle(.expandedPlayer)
    }
}

extension PlayerButtonConfig {
    static var expandedPlayer: Self {
        Self(
            labelColor: .init(Palette.PlayerCard.opaque),
            tint: .init(Palette.PlayerCard.translucent.withAlphaComponent(0.3)),
            pressedColor: .init(Palette.PlayerCard.opaque),
            disabledColor: .init(Palette.PlayerCard.translucent)
        )
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController()
    ZStack(alignment: .top) {
        PreviewBackground()
        VStack {
            Text("Header")
                .blendMode(.overlay)
            PlayerButtons(spacing: UIScreen.size.width * 0.14)
            Text("Footer")
                .blendMode(.overlay)
        }
        .foregroundStyle(Color(Palette.PlayerCard.opaque))
    }
    .environment(playerController)
}
