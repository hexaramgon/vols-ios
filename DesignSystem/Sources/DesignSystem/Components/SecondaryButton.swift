//
//  SecondaryButton.swift
//  DesignSystem
//
//  The quiet sibling of `PrimaryButton` — a `vControl` (ink @ 0.08) capsule
//  with an ink @ 0.70 label. Same two sizes and the same busy / disabled
//  treatment as `PrimaryButton`, so a primary + secondary pair line up.
//

import SwiftUI

public struct SecondaryButton: View {
    private let title: String
    private let icon: LucideIcon.Name?
    private let size: PrimaryButton.Size
    private let expands: Bool
    private let busy: Bool
    private let enabled: Bool
    private let labelColor: Color
    private let disabledLabelColor: Color
    private let action: () -> Void

    /// - Parameters:
    ///   - icon: optional leading Lucide glyph.
    ///   - expands: false renders a hugging capsule instead of full width.
    ///   - busy: shows a spinner in place of the label and blocks taps.
    ///   - enabled: false blocks taps and dims the label to `vText4`.
    ///   - labelColor / disabledLabelColor: a darker label where a screen
    ///     wants it (defaults: `vControlLabel` / `vText4`).
    public init(
        _ title: String,
        icon: LucideIcon.Name? = nil,
        size: PrimaryButton.Size = .full,
        expands: Bool = true,
        busy: Bool = false,
        enabled: Bool = true,
        labelColor: Color = .vControlLabel,
        disabledLabelColor: Color = .vText4,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.size = size
        self.expands = expands
        self.busy = busy
        self.enabled = enabled
        self.labelColor = labelColor
        self.disabledLabelColor = disabledLabelColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().tint(labelColor)
                } else {
                    HStack(spacing: 6) {
                        if let icon { LucideIcon(icon, .md) }
                        Text(title).font(size.font).lineLimit(1)
                    }
                    .modifier(CapsuleLabelFit(expands: expands))
                }
            }
            .foregroundStyle(enabled ? labelColor : disabledLabelColor)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: size.height)
            .padding(.horizontal, expands ? 0 : (icon == nil ? 24 : 20))
            .background(Color.vControl, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .animation(.easeInOut(duration: 0.18), value: enabled)
    }
}

#Preview {
    VStack(spacing: 16) {
        SecondaryButton("Cancel") {}
        SecondaryButton("Message", icon: .messageCircle, size: .inline, expands: false) {}
        SecondaryButton("Disabled", enabled: false) {}
    }
    .padding()
    .background(Color.vBase)
}
