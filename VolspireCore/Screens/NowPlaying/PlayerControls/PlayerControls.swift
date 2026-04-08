//
//  PlayerControls.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import MediaLibrary
import SwiftUI

struct PlayerControls: View {
    @Environment(PlayerController.self) var model

    var body: some View {
        GeometryReader {
            let size = $0.size
            let spacing = size.verticalSpacing / 8
            VStack(spacing: spacing )
                {
                    trackInfo

                    TimingIndicator(spacing: spacing)
                        .padding(.top, spacing)
                        .padding(.horizontal, ViewConst.playerCardPaddings)
                        .padding(.horizontal, -ElasticSliderConfig.playbackProgress.growth)
                    
                    PlayerButtons(spacing: size.width * 0.05)
                        .padding(.horizontal, ViewConst.playerCardPaddings)
                }
            }
               
        
        .sheet(isPresented: Bindable(model).showingEffectsSheet) {
            AudioEffectsSheet()
                .environment(model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private extension CGSize {
    var verticalSpacing: CGFloat { height * 0.04 }
}

private extension PlayerControls {
    var palette: Palette.PlayerCard.Type {
        UIColor.palette.playerCard.self
    }

    @ViewBuilder
    var trackInfo: some View {
        HStack(alignment: .center) {
            // Artist profile picture (always reserve space)
            Group {
                if let urlString = model.trackDetail?.artist?.profileImageUrl,
                   let url = URL(string: urlString) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .padding(.leading, ViewConst.playerCardPaddings)
            .onTapGesture {
                if let userId = model.trackDetail?.artist?.userId {
                    model.pendingProfileNavigation = userId
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                let fade = ViewConst.playerCardPaddings
                let cfg = MarqueeText.Config(leftFade: 0, rightFade: fade)
                let title = model.display.title.isEmpty ? " " : model.display.title
                let subtitle = model.display.subtitle.isEmpty ? " " : model.display.subtitle
                MarqueeText(title, config: cfg)
                    .transformEffect(.identity)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(palette.opaque))
                    .id(model.display)
                MarqueeText(subtitle, config: cfg)
                    .transformEffect(.identity)
                    .foregroundStyle(Color(palette.opaque))
                    .blendMode(.overlay)
                    .id(model.display)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            fxButton
                .padding(.trailing, ViewConst.playerCardPaddings)
        }
    }

    var fxButton: some View {
        let isActive = model.audioEffects != .default
        return Button {
            model.showingEffectsSheet = true
        } label: {
            VStack() {
                Image(systemName: "wand.and.stars")
                    .font(.body)
                Text("FX")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundStyle(isActive ? Color.green : Color(palette.translucent))
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
