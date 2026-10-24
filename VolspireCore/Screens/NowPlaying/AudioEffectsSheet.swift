//
//  AudioEffectsSheet.swift
//  Volspire
//
//  Playback-speed control with a preserve-pitch toggle. Same flow as ever
//  (read-out, slider, toggles, reset), drawn with the app's pieces: ink
//  tokens, the Settings group card + rows + ink switch, the capsule button.
//

import DesignSystem
import Player
import Services
import SwiftUI

struct AudioEffectsSheet: View {
    @Environment(PlayerController.self) var controller

    /// Live slider value while dragging; committed to the player on release.
    @State private var localSpeed: Float?

    private var speedValue: Float { localSpeed ?? controller.audioEffects.speed }
    private var isModified: Bool { controller.audioEffects != .default }

    var body: some View {
        VStack(spacing: 22) {
            hero
            speedSlider
            togglesCard
            if isModified { resetButton }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        // Stays dark like the rest of the player.
        .sheetBackground(dragIndicator: false, alwaysDark: true)
    }
}

// MARK: - Pieces

private extension AudioEffectsSheet {
    /// Big live speed read-out + label.
    var hero: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f×", speedValue))
                .font(.appDisplayLarge)
                .monospacedDigit()
                .foregroundStyle(Color.vText)
            Text("Playback speed")
                .font(.appCallout)
                .foregroundStyle(Color.vText3)
        }
    }

    var speedSlider: some View {
        VStack(spacing: 8) {
            // The player-style bar, not a stock `Slider` (see `.inlineScrub`);
            // the old `step: 0.01` becomes rounding in the binding's setter.
            ElasticSlider(
                value: Binding(
                    get: { Double(speedValue) },
                    set: { localSpeed = Float(($0 / 0.01).rounded() * 0.01) }
                ),
                in: 0.25 ... 2.0,
                onActive: { active in
                    if !active, let val = localSpeed { commitSpeed(val) }
                }
            )
            .sliderStyle(.inlineScrub)
            .frame(height: 22)
            // Tick as the speed moves through each 0.05× step (quantised so it's a
            // gentle ratchet, not a continuous buzz).
            .sensoryFeedback(.selection, trigger: Int((speedValue / 0.05).rounded()))

            // 0.25× far-left, 2× far-right, 1× at its true spot on the track.
            GeometryReader { geo in
                let onePos = CGFloat((1.0 - 0.25) / (2.0 - 0.25))
                Text("0.25×")
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                Text("2×")
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
                Text("1×")
                    .position(x: geo.size.width * onePos, y: geo.size.height / 2)
            }
            .frame(height: 18)
            .font(.appFootnote)
            .monospacedDigit()
            .foregroundStyle(Color.vText3)
        }
    }

    /// Both toggle rows straight on the sheet — no card, no divider, just
    /// the ink switch.
    var togglesCard: some View {
        VStack(spacing: 0) {
            SettingsRow(
                title: "Preserve pitch",
                caption: controller.audioEffects.preservePitch
                    ? "Speed changes tempo only"
                    : "Speed changes pitch too",
                titleFont: .appBodyMedium,
                captionFont: .appFootnote
            ) {
                inkToggle(Binding(get: { controller.audioEffects.preservePitch }, set: { setPreservePitch($0) }))
            }

            SettingsRow(
                title: "Carry to next track",
                caption: controller.persistAudioEdits
                    ? "Settings apply to every track"
                    : "Settings reset on track change",
                titleFont: .appBodyMedium,
                captionFont: .appFootnote
            ) {
                inkToggle(Binding(get: { controller.persistAudioEdits }, set: { controller.persistAudioEdits = $0 }))
            }
        }
        // The rows keep their own 16pt inset; with no card around them, pull
        // them out so the text lines up with the slider's edges.
        .padding(.horizontal, -16)
    }

    func inkToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.ink)
            // A size up from the stock 44×24 switch, to match this sheet's
            // larger type (scaled, so layout reserves the bigger footprint).
            .scaleEffect(1.25)
            .frame(width: 55, height: 30)
    }

    var resetButton: some View {
        Button {
            localSpeed = nil
            controller.applyEffects(.default)
        } label: {
            CapsuleButtonLabel(title: "Reset", style: .secondary, expands: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Actions

private extension AudioEffectsSheet {
    func commitSpeed(_ value: Float) {
        var fx = controller.audioEffects
        fx.speed = value
        controller.applyEffects(fx)
        AnalyticsService.shared?.log(.audioSettingsChanged, trackId: controller.state.currentMediaID?.value, metadata: ["setting": "speed", "speed": .double(Double(fx.speed)), "preserve_pitch": .bool(fx.preservePitch)])
        localSpeed = nil
    }

    func setPreservePitch(_ on: Bool) {
        var fx = controller.audioEffects
        fx.preservePitch = on
        controller.applyEffects(fx)
        AnalyticsService.shared?.log(.audioSettingsChanged, trackId: controller.state.currentMediaID?.value, metadata: ["setting": "preserve_pitch", "speed": .double(Double(fx.speed)), "preserve_pitch": .bool(fx.preservePitch)])
    }
}

#Preview {
    @Previewable @State var controller = PlayerController.stub
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AudioEffectsSheet()
                .environment(controller)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
        }
}
