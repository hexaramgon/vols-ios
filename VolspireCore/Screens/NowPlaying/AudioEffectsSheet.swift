//
//  AudioEffectsSheet.swift
//  Volspire
//
//  Playback-speed control with a preserve-pitch toggle. Styled to sit with the
//  rest of the player: frosted panel, Geist type, white accents, soft cards.
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
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        // Darker frosted panel to match the web's modal background.
        .sheetBackground()
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
                .foregroundStyle(.white)
            Text("Playback speed")
                .font(.appCaption2Medium)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    var speedSlider: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(get: { speedValue }, set: { localSpeed = $0 }),
                in: 0.25 ... 2.0,
                step: 0.01,
                onEditingChanged: { editing in
                    if !editing, let val = localSpeed { commitSpeed(val) }
                }
            )
            .tint(.white)
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
            .frame(height: 14)
            .font(.appCaption2)
            .foregroundStyle(.white.opacity(0.35))
        }
    }

    /// Both toggle rows grouped in one card with a hairline between them.
    var togglesCard: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: "Preserve pitch",
                subtitle: controller.audioEffects.preservePitch
                    ? "Speed changes tempo only"
                    : "Speed changes pitch too",
                isOn: controller.audioEffects.preservePitch,
                action: { setPreservePitch($0) }
            )

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.leading, 16)

            toggleRow(
                title: "Carry to next track",
                subtitle: controller.persistAudioEdits
                    ? "Settings apply to every track"
                    : "Settings reset on track change",
                isOn: controller.persistAudioEdits,
                action: { controller.persistAudioEdits = $0 }
            )
        }
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func toggleRow(title: String, subtitle: String, isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appCallout)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            fxToggle(isOn: isOn, action: action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    var resetButton: some View {
        Button {
            localSpeed = nil
            controller.applyEffects(.default)
        } label: {
            Text("Reset")
                .font(.appSubheadlineMedium)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Soft switch matching the player's white accent: ON = white / dark knob.
    func fxToggle(isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        Button { action(!isOn) } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.white : Color.white.opacity(0.22))
                    .frame(width: 44, height: 26)
                Circle()
                    .fill(isOn ? Color.black : Color.white.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isOn)
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
