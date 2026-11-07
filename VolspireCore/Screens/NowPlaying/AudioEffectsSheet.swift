//
//  AudioEffectsSheet.swift
//  Volspire
//
//  Speed | EQ tabs under one header. Speed: `EffectSliderRow` (label + value
//  over the now-playing slider) and the ink-switch rows. EQ: `EqualizerPanel`
//  (presets + draggable response curve). Each tab has its own Reset. Tabs
//  crossfade rather than slide.
//

import DesignSystem
import Player
import Services
import SwiftUI

struct AudioEffectsSheet: View {
    @Environment(PlayerController.self) var controller

    enum Tab: String, CaseIterable, Identifiable {
        case speed = "Speed"
        case equalizer = "EQ"
        var id: Self { self }
    }

    /// Live slider value while dragging; committed to the player on release.
    @State private var localSpeed: Float?
    @State private var tab: Tab = .speed
    /// A finger is on the EQ curve.
    @State private var draggingCurve = false

    private var speedValue: Float { localSpeed ?? controller.audioEffects.speed }

    /// Tabs with a non-default setting get a dot — same rule as their Reset
    /// buttons and the player's FX button.
    private var activeTabs: Set<Tab> {
        var tabs: Set<Tab> = []
        if controller.audioEffects != .default { tabs.insert(.speed) }
        if !controller.equalizer.isFlat { tabs.insert(.equalizer) }
        return tabs
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // The app's sheet header (Collab Request / Respond).
            SheetHeader(icon: .slidersHorizontal, title: "Audio effects", subtitle: "Speed, pitch & EQ") { dismiss() }

            EffectsTabPicker(selection: $tab, dotted: activeTabs)
                .padding(.horizontal, 24)

            ZStack(alignment: .top) {
                switch tab {
                case .speed: speedTab.transition(.opacity)
                case .equalizer: equalizerTab.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Swipe-down closes the sheet from either tab — except while a finger
        // is dragging an EQ point, so a downward drag moves the point, not
        // the sheet.
        .interactiveDismissDisabled(draggingCurve)
        // Stays dark like the rest of the player.
        .sheetBackground(dragIndicator: false, alwaysDark: true)
    }
}

// MARK: - Tabs

private extension AudioEffectsSheet {
    var speedTab: some View {
        ScrollView {
            VStack(spacing: 18) {
                EffectSliderRow(
                    label: "Speed",
                    valueText: String(format: "%.2f×", speedValue),
                    value: Binding(get: { Double(speedValue) }, set: { localSpeed = Float($0) }),
                    range: 0.25 ... 2.0,
                    step: 0.01,
                    // A gentle ratchet every 0.05×, not a buzz on each 0.01.
                    hapticStep: 0.05,
                    onRelease: { if let val = localSpeed { commitSpeed(val) } }
                )
                togglesCard
                if controller.audioEffects != .default {
                    resetButton("Reset speed") {
                        localSpeed = nil
                        controller.applyEffects(.default)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// No ScrollView: the curve's drag would fight it, and the tab fits.
    var equalizerTab: some View {
        VStack(spacing: 16) {
            EqualizerPanel(
                equalizer: controller.equalizer,
                onChange: { controller.applyEqualizer($0) },
                onCommit: logEqualizerChange,
                onDraggingChanged: { draggingCurve = $0 }
            )
            if !controller.equalizer.isFlat {
                resetButton("Reset EQ") {
                    controller.applyEqualizer(.flat)
                    logEqualizerChange()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }
}

// MARK: - Pieces

private extension AudioEffectsSheet {
    /// Both toggle rows straight on the sheet — no card, no divider.
    var togglesCard: some View {
        VStack(spacing: 0) {
            SettingsRow(
                title: "Preserve pitch",
                caption: controller.audioEffects.preservePitch
                    ? "Speed changes tempo only"
                    : "Speed changes pitch too",
                titleFont: .appBody,
                captionFont: .appFootnote
            ) {
                inkToggle(Binding(get: { controller.audioEffects.preservePitch }, set: { setPreservePitch($0) }))
            }

            SettingsRow(
                title: "Carry to next track",
                caption: controller.persistAudioEdits
                    ? "Speed applies to every track"
                    : "Speed resets on track change",
                titleFont: .appBody,
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

    func resetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CapsuleButtonLabel(title: title, style: .secondary, expands: true)
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

    func logEqualizerChange() {
        let eq = controller.equalizer
        var metadata: [String: AnalyticsValue] = [
            "setting": "equalizer",
            "preset": .string(EqualizerPreset(matching: eq)?.rawValue ?? "custom")
        ]
        for (index, band) in AudioEqualizer.bands.enumerated() {
            let key = band.label.lowercased().replacingOccurrences(of: " ", with: "_")
            metadata["\(key)_db"] = .double(Double(eq.gains[index]))
            metadata["\(key)_hz"] = .double(Double(eq.frequencies[index]))
        }
        AnalyticsService.shared?.log(.audioSettingsChanged, trackId: controller.state.currentMediaID?.value, metadata: metadata)
    }

    func setPreservePitch(_ on: Bool) {
        var fx = controller.audioEffects
        fx.preservePitch = on
        controller.applyEffects(fx)
        AnalyticsService.shared?.log(.audioSettingsChanged, trackId: controller.state.currentMediaID?.value, metadata: ["setting": "preserve_pitch", "speed": .double(Double(fx.speed)), "preserve_pitch": .bool(fx.preservePitch)])
    }
}

/// Two-segment pill: a track with the selected segment filled like an "on"
/// FilterChip. `dotted` tabs get a small dot when their setting is changed,
/// so it's visible from the other tab.
private struct EffectsTabPicker: View {
    @Binding var selection: AudioEffectsSheet.Tab
    let dotted: Set<AudioEffectsSheet.Tab>
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AudioEffectsSheet.Tab.allCases) { tab in
                let isOn = tab == selection
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue).font(.appFootnoteMedium)
                        if dotted.contains(tab) {
                            Circle().frame(width: 5, height: 5)
                        }
                    }
                    .foregroundStyle(isOn ? Color.vOnInverse : Color.inkText(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background {
                        if isOn {
                            Capsule()
                                .fill(Color.vInverse)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.vRowActive, in: Capsule())
        .animation(.snappy(duration: 0.25), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// One slider setting: name and value read-out over the same elastic bar
/// (and `.playbackProgress` style) as the now-playing scrubber, with a
/// selection tick each `hapticStep` so steps (and EQ's 0 dB) are easy to
/// find by feel. Used for speed and every EQ band.
private struct EffectSliderRow: View {
    let label: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let hapticStep: Double
    let onRelease: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).foregroundStyle(Color.vText)
                Spacer(minLength: 0)
                Text(valueText).foregroundStyle(Color.vText2)
            }
            .font(.appBody)
            .monospacedDigit()

            ElasticSlider(
                value: Binding(
                    get: { value },
                    set: { value = ($0 / step).rounded() * step }
                ),
                in: range,
                onActive: { active in
                    if !active { onRelease() }
                }
            )
            .sliderStyle(.playbackProgress)
            .frame(height: 22)
            // The resting bar is inset by `growth` (it widens while dragged);
            // pull it out so it lines up with the label row, like the player.
            .padding(.horizontal, -ElasticSliderConfig.playbackProgress.growth)
            .sensoryFeedback(.selection, trigger: Int((value / hapticStep).rounded()))
        }
    }
}

#Preview {
    @Previewable @State var controller = PlayerController.stub
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AudioEffectsSheet()
                .environment(controller)
                .presentationDetents([.height(560)])
                .presentationDragIndicator(.visible)
        }
}
