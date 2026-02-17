//
//  TimingIndicator.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct TimingIndicator: View {
    let spacing: CGFloat
    @Environment(PlayerController.self) var controller
    @State private var scrubValue: Double = 0

    private var duration: Double {
        controller.progress?.duration ?? 0
    }

    private var elapsed: Double {
        controller.progress?.elapsedTime ?? 0
    }

    private var displayValue: Double {
        controller.isScrubbing ? scrubValue : elapsed
    }

    var body: some View {
        ElasticSlider(
            value: Binding(
                get: { displayValue },
                set: { scrubValue = $0 }
            ),
            in: 0 ... max(duration, 1),
            leadingLabel: {
                label(leadingLabelText)
            },
            trailingLabel: {
                label(trailingLabelText)
            },
            onActive: { active in
                controller.isScrubbing = active
                if active {
                    scrubValue = elapsed
                } else {
                    controller.seek(to: scrubValue)
                }
            }
        )
        .sliderStyle(.playbackProgress)
        .frame(height: 60)
        .transformEffect(.identity)
    }
}

private extension TimingIndicator {
    func label(_ text: String) -> some View {
        Text(text)
            .font(.appFont.timingIndicator)
            .padding(.top, 11)
    }

    var leadingLabelText: String {
        displayValue.asTimeString(style: .positional)
    }

    var trailingLabelText: String {
        ((duration - displayValue) * -1.0).asTimeString(style: .positional)
    }

    var palette: Palette.PlayerCard.Type {
        UIColor.palette.playerCard.self
    }
}

extension ElasticSliderConfig {
    static var playbackProgress: Self {
        Self(
            labelLocation: .bottom,
            maxStretch: 0,
            minimumTrackActiveColor: Color(Palette.PlayerCard.opaque),
            minimumTrackInactiveColor: Color(Palette.PlayerCard.translucent),
            maximumTrackColor: Color(Palette.PlayerCard.translucent),
            blendMode: .overlay,
            syncLabelsStyle: true
        )
    }
}

#Preview {
    ZStack {
        PreviewBackground()
        TimingIndicator(spacing: 10)
            .padding(.horizontal)
    }
}

extension BinaryFloatingPoint {
    func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = style
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: TimeInterval(self)) ?? ""
    }
}
