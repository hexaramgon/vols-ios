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

    /// A light tick for moving through discrete values (e.g. a slider step).
    @MainActor public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
