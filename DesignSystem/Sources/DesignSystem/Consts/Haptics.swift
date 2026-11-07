//
//  Haptics.swift
//  Volspire
//
//  Lightweight haptic-feedback helpers, shared across the app so feedback feels
//  consistent (save, toggles, fine adjustments).
//

import UIKit

public enum Haptics {
    /// A positive confirmation (e.g. a track was saved).
    @MainActor public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A short tap (e.g. toggling something off).
    @MainActor public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Saving something (track, listing, pack): its own subtle signature — two
    /// soft taps ~70ms apart, the second a touch stronger ("tick-tick"),
    /// distinct from the success buzz of creating / adding.
    @MainActor public static func save() {
        let first = UIImpactFeedbackGenerator(style: .soft)
        let second = UIImpactFeedbackGenerator(style: .light)
        first.prepare()
        second.prepare()
        first.impactOccurred(intensity: 0.55)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            second.impactOccurred(intensity: 0.85)
        }
    }

    /// Un-saving: a single faint soft tap.
    @MainActor public static func unsave() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
    }

    /// A light tick for moving through discrete values (e.g. a slider step).
    @MainActor public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
