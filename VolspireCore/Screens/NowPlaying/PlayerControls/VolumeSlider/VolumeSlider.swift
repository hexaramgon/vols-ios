//
//  VolumeSlider.swift
//  Volspire
//
//

import DesignSystem
import MediaPlayer
import SwiftUI

public struct VolumeSlider: View {
    @State var minVolumeAnimationTrigger: Bool = false
    @State var maxVolumeAnimationTrigger: Bool = false
    let range = 0.0 ... 1
    @StateObject private var viewModel = VolumeSliderViewModel()

    public var body: some View {
        ZStack {
            // invisible MPVolumeView
            MPVolumeViewWrapper(proxy: viewModel.volumeViewProxy)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

            ElasticSlider(
                value: $viewModel.currentVolume,
                in: range,
                leadingLabel: {
                    LucideIcon(.volume1, .sm)
                        .padding(.trailing, 10)
                },
                trailingLabel: {
                    LucideIcon(.volume2, .sm)
                        .padding(.leading, 10)
                },
                onValueChanged: { [weak viewModel] in
                    viewModel?.setVolume($0)
                },
                onActive: { [weak viewModel] in
                    viewModel?.setSliderActive($0)
                }
            )
            .sliderStyle(.volume)
            .font(.appSubheadline)
            .onChange(of: viewModel.currentVolume) {
                if viewModel.currentVolume == range.lowerBound {
                    minVolumeAnimationTrigger.toggle()
                }
                if viewModel.currentVolume == range.upperBound {
                    maxVolumeAnimationTrigger.toggle()
                }
            }
            .frame(height: 50)
        }
    }
}

extension ElasticSliderConfig {
    static var volume: Self {
        Self(
            labelLocation: .side,
            maxStretch: 10,
            minimumTrackActiveColor: Color(Palette.PlayerCard.opaque),
            minimumTrackInactiveColor: Color(Palette.PlayerCard.translucent),
            maximumTrackColor: Color(Palette.PlayerCard.translucent),
            blendMode: .overlay,
            syncLabelsStyle: true
        )
    }
}

final class MPVolumeViewProxy {
    var mpVolumeView: MPVolumeView?
}

private struct MPVolumeViewWrapper: UIViewRepresentable {
    var proxy: MPVolumeViewProxy

    func makeUIView(context _: Context) -> MPVolumeView {
        let mpView = MPVolumeView()
        proxy.mpVolumeView = mpView
        mpView.alpha = 0.0001
        mpView.isUserInteractionEnabled = false
        mpView.clipsToBounds = true
        return mpView
    }

    func updateUIView(_ uiView: MPVolumeView, context _: Context) {
        uiView.alpha = 0.0001
        uiView.isUserInteractionEnabled = false
    }
}

#Preview {
    ZStack {
        PreviewBackground()
        VolumeSlider()
    }
    .ignoresSafeArea()
}
