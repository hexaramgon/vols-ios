//
//  AudioEffectsSheet.swift
//  Volspire
//
//  Bottom sheet with sliders for Speed and Pitch controls.
//

import Player
import SwiftUI

struct AudioEffectsSheet: View {
    @Environment(PlayerController.self) var controller
    @Environment(\.dismiss) var dismiss
    @State private var localSpeed: Float?
    @State private var localPitch: Float?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    speedSection
                    Divider().overlay(Color.white.opacity(0.1))
                    pitchSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle("Audio FX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        controller.applyEffects(.default)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(.systemBackground).opacity(0.95))
        }
    }
}

// MARK: - Speed

private extension AudioEffectsSheet {
    var speedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Speed", systemImage: "gauge.with.needle")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.2fx", localSpeed ?? controller.audioEffects.speed))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { localSpeed ?? controller.audioEffects.speed },
                    set: { localSpeed = $0 }
                ),
                in: 0.25 ... 2.0,
                step: 0.05,
                onEditingChanged: { editing in
                    if !editing, let val = localSpeed {
                        var fx = controller.audioEffects
                        fx.speed = val
                        controller.applyEffects(fx)
                        localSpeed = nil
                    }
                }
            )
            .tint(.green)

            HStack {
                Text("0.25x")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("1.0x")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("2.0x")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Quick presets
            HStack(spacing: 8) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    speedPresetButton(rate: Float(rate))
                }
            }
        }
    }

    func speedPresetButton(rate: Float) -> some View {
        let isSelected = abs(controller.audioEffects.speed - rate) < 0.01
        return Button {
            var fx = controller.audioEffects
            fx.speed = rate
            controller.applyEffects(fx)
        } label: {
            Text(String(format: rate == floor(rate) ? "%.0fx" : "%.2fx", rate))
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.green : Color.white.opacity(0.1))
                )
                .foregroundStyle(isSelected ? .black : .white)
        }
    }
}

// MARK: - Pitch

private extension AudioEffectsSheet {
    var pitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pitch", systemImage: "music.note")
                    .font(.headline)
                Spacer()
                let semitones = (localPitch ?? controller.audioEffects.pitch) / 100
                Text(String(format: "%+.1f st", semitones))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { localPitch ?? controller.audioEffects.pitch },
                    set: { localPitch = $0 }
                ),
                in: -1200 ... 1200,
                step: 100,
                onEditingChanged: { editing in
                    if !editing, let val = localPitch {
                        var fx = controller.audioEffects
                        fx.pitch = val
                        controller.applyEffects(fx)
                        localPitch = nil
                    }
                }
            )
            .tint(.blue)

            HStack {
                Text("-12 st")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("+12 st")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Quick presets
            HStack(spacing: 8) {
                ForEach([-500, -200, 0, 200, 500], id: \.self) { cents in
                    pitchPresetButton(cents: Float(cents))
                }
            }
        }
    }

    func pitchPresetButton(cents: Float) -> some View {
        let isSelected = abs(controller.audioEffects.pitch - cents) < 1
        let semitones = cents / 100
        let label = cents == 0 ? "Normal" : String(format: "%+.0f st", semitones)
        return Button {
            var fx = controller.audioEffects
            fx.pitch = cents
            controller.applyEffects(fx)
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.white.opacity(0.1))
                )
                .foregroundStyle(isSelected ? .white : .white)
        }
    }
}

#Preview {
    @Previewable @State var controller = PlayerController.stub
    AudioEffectsSheet()
        .environment(controller)
}
