//
//  MinimumHitArea.swift
//  DesignSystem
//
//  Grows a small control's tap area to Apple's 44pt minimum without changing
//  how it looks or how it lays out: pad out, take the hit shape, pad back in.
//

import SwiftUI

public extension View {
    /// Makes a `size`-pt control tappable across at least `minimum` points.
    /// Apply after the control's `.frame`/`.background`, in place of
    /// `.contentShape(.rect)`.
    func minimumHitArea(for size: CGFloat, minimum: CGFloat = 44) -> some View {
        let inset = max(0, (minimum - size) / 2)
        return padding(inset)
            .contentShape(.rect)
            .padding(-inset)
    }
}
